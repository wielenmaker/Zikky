//! Vim mode for the code editor. It sees keys before the editor does (gooey's
//! `Window.key_capture`): normal, insert and visual (v / V) modes, counts, the
//! d / c / y operators and one register (yanks also reach the clipboard).

const std = @import("std");
const gooey = @import("gooey");
const m = @import("vim_motion.zig");
const AppState = @import("state.zig").AppState;
const find = @import("find.zig");

const TextAreaState = gooey.widgets.TextAreaState;
const KeyCode = gooey.input.KeyCode;
const Modifiers = gooey.input.Modifiers;

pub const Mode = enum { normal, insert, visual, visual_line };

/// Where a motion lands; `lines` makes an operator linewise, `incl` takes the last character too.
const Target = struct { pos: usize, lines: bool = false, incl: bool = false };

pub var vim = Vim{};

/// `Window.key_capture`: only while the editor has focus; ⌘ shortcuts pass through.
pub fn capture(w: *gooey.Window, event: gooey.input.InputEvent) bool {
    const k = switch (event) {
        .key_down => |k| k,
        else => return false,
    };
    const s = w.getRootState(AppState) orelse return false;
    const ce = s.editor(w) orelse return false;
    if (!ce.isFocused()) return false;
    const ta = &ce.text_area;
    // A click ends visual mode.
    if (vim.visual() and !ta.hasSelection()) vim.mode = .normal;
    if (k.key == .escape) return vim.escape(ta);
    if (vim.mode == .insert or k.modifiers.cmd) return false;
    if (k.modifiers.ctrl) return vim.ctrl(ta, k.key);
    // `/` and `?` search with the find bar.
    if (vim.pending == null and vim.op == null) if (k.characters) |c| if (c.len == 1 and (c[0] == '/' or c[0] == '?')) {
        vim.count = 0;
        find.openVim(s, w, c[0] == '?');
        return true;
    };
    vim.char(ta, switch (k.key) {
        .left, .delete => 'h',
        .right => 'l',
        .up => 'k',
        .down, .@"return" => 'j',
        else => if (k.characters) |c| (if (c.len == 1) c[0] else 0) else 0,
    });
    return true;
}

const Vim = struct {
    mode: Mode = .normal,
    count: usize = 0,
    op: ?u8 = null,
    op_count: usize = 0,
    /// `g`, `r`, `f`, `F`, `t`, `T`, or a text object's `i` / `a`, waiting for its second key.
    pending: ?u8 = null,
    /// Visual mode's fixed end and moving end (the editor only shows the selection).
    anchor: usize = 0,
    cur: usize = 0,
    /// The byte column `j` / `k` keep (`maxInt` after `$`), while the cursor stays at `col_at`.
    col: usize = 0,
    col_at: usize = 0,
    reg: std.ArrayList(u8) = .empty,
    reg_lines: bool = false,

    fn escape(self: *Vim, ta: *TextAreaState) bool {
        const t = ta.getText();
        switch (self.mode) {
            .insert => ta.select(null, m.clamp(t, m.left(t, ta.cursor_byte))),
            .visual, .visual_line => ta.select(null, self.cur),
            .normal => {},
        }
        self.* = .{ .reg = self.reg, .reg_lines = self.reg_lines };
        return true;
    }

    fn ctrl(self: *Vim, ta: *TextAreaState, key: KeyCode) bool {
        const half: isize = @intFromFloat(@max(1, ta.viewport_height / @max(1, ta.line_height) / 2));
        switch (key) {
            .r => {
                press(ta, .z, .{ .cmd = true, .shift = true });
                ta.select(null, m.clamp(ta.getText(), ta.cursor_byte));
            },
            .d, .u => {
                const t = ta.getText();
                const i = self.at(ta);
                self.go(ta, .{ .pos = m.vertical(t, i, if (key == .d) half else -half, self.wantCol(t, i)) });
                self.col_at = self.cur;
            },
            // Others reach the keymap.
            else => return false,
        }
        return true;
    }

    fn at(self: *Vim, ta: *TextAreaState) usize {
        return if (self.visual()) self.cur else ta.cursor_byte;
    }

    fn visual(self: *Vim) bool {
        return self.mode == .visual or self.mode == .visual_line;
    }

    fn char(self: *Vim, ta: *TextAreaState, c: u8) void {
        if (self.pending == null and (c >= '1' and c <= '9' or c == '0' and self.count > 0)) {
            self.count = self.count * 10 + c - '0';
            return;
        }
        const counted = self.count > 0 or self.op_count > 0;
        const n = @max(self.op_count, 1) * @max(self.count, 1);
        const o = self.op;
        const p = self.pending;
        self.count = 0;
        self.op_count = 0;
        self.op = null;
        self.pending = null;

        const t = ta.getText();
        const i = self.at(ta);
        if (p) |first| return self.pair(ta, first, c, o, n, counted);
        if (self.motion(t, i, c, n, counted, o)) |tg| {
            if (o) |op| return self.operate(ta, op, i, tg);
            self.go(ta, tg);
            if (c == '$') self.col = std.math.maxInt(usize);
            if (c == 'j' or c == 'k' or c == '$') self.col_at = self.cur;
            return;
        }
        // `i` / `a` after an operator or in visual mode start a text object (iw, a", i( …).
        if ((o != null or self.visual()) and (c == 'i' or c == 'a')) {
            self.pending = c;
            self.op = o;
            return;
        }
        if (self.visual() and std.mem.indexOfScalar(u8, "gfFtT", c) == null) return self.visualKey(ta, c);
        switch (c) {
            'g', 'r', 'f', 'F', 't', 'T' => {
                self.pending = c;
                self.op = o;
                self.count = if (counted) n else 0;
            },
            'd', 'c', 'y' => if (o == c) {
                self.operate(ta, c, i, .{ .pos = m.vertical(t, i, @intCast(n - 1), 0), .lines = true });
            } else if (o == null) {
                self.op = c;
                self.op_count = if (counted) n else 0;
            },
            'D', 'C' => self.operate(ta, std.ascii.toLower(c), i, .{ .pos = m.lineEnd(t, i) }),
            'Y' => self.operate(ta, 'y', i, .{ .pos = i, .lines = true }),
            'S' => self.operate(ta, 'c', i, .{ .pos = i, .lines = true }),
            'x', 's' => self.operate(ta, if (c == 'x') 'd' else 'c', i, .{ .pos = @min(rep(m.next, t, i, n), m.lineEnd(t, i)) }),
            'X' => self.operate(ta, 'd', i, .{ .pos = rep(m.left, t, i, n) }),
            'i' => self.insert(ta, i),
            'a' => self.insert(ta, @min(m.next(t, i), m.lineEnd(t, i))),
            'I' => self.insert(ta, m.firstNonBlank(t, i)),
            'A' => self.insert(ta, m.lineEnd(t, i)),
            'o', 'O' => self.openLine(ta, i, c == 'o'),
            'p', 'P' => self.paste(ta, i, c == 'p', n),
            'J' => for (0..n) |_| join(ta),
            '~' => self.toggleCase(ta, i),
            'u' => {
                for (0..n) |_| press(ta, .z, .{ .cmd = true });
                ta.select(null, m.clamp(ta.getText(), ta.cursor_byte));
            },
            'v' => self.startVisual(i, .visual),
            'V' => self.startVisual(i, .visual_line),
            else => {},
        }
        if (self.visual()) self.show(ta);
    }

    fn motion(self: *Vim, t: []const u8, i: usize, c: u8, n: usize, counted: bool, o: ?u8) ?Target {
        const lines: isize = @intCast(n);
        return switch (c) {
            'h' => .{ .pos = rep(m.left, t, i, n) },
            'l' => .{ .pos = if (o == null) rep(m.right, t, i, n) else @min(rep(m.next, t, i, n), m.lineEnd(t, i)) },
            'j' => .{ .pos = m.vertical(t, i, lines, self.wantCol(t, i)), .lines = true },
            'k' => .{ .pos = m.vertical(t, i, -lines, self.wantCol(t, i)), .lines = true },
            // `cw` changes to the word's end; `dw` stops at the line's end.
            'w' => if (o == 'c' and i < t.len and !std.ascii.isWhitespace(t[i]))
                .{ .pos = rep(m.wordEnd, t, i, n), .incl = true }
            else
                .{ .pos = if (o == null) rep(m.wordForward, t, i, n) else @min(rep(m.wordForward, t, i, n), m.lineEnd(t, i)) },
            'b' => .{ .pos = rep(m.wordBack, t, i, n) },
            'e' => .{ .pos = rep(m.wordEnd, t, i, n), .incl = true },
            '0' => .{ .pos = m.lineStart(t, i) },
            '^' => .{ .pos = m.firstNonBlank(t, i) },
            '$' => .{ .pos = m.lineEnd(t, m.vertical(t, i, lines - 1, 0)) },
            'G' => .{ .pos = m.firstNonBlank(t, m.vertical(t, 0, if (counted) lines - 1 else std.math.maxInt(isize), 0)), .lines = true },
            '}' => .{ .pos = repDir(m.paragraph, t, i, n, true) },
            // The next match of the last search (`n` its way, `N` the other).
            'n', 'N' => blk: {
                var p = i;
                for (0..n) |_| p = (find.nextFrom(t, p, find.vimForward(c == 'n')) orelse break :blk null).start;
                break :blk .{ .pos = p };
            },
            '{' => .{ .pos = repDir(m.paragraph, t, i, n, false) },
            else => null,
        };
    }

    /// The second key of `gg`, `r`, `f`, `F`, `t`, `T` and text objects.
    fn pair(self: *Vim, ta: *TextAreaState, first: u8, c: u8, o: ?u8, n: usize, counted: bool) void {
        const t = ta.getText();
        const i = self.at(ta);
        const tg: Target = switch (first) {
            'g' => if (c == 'g') .{ .pos = m.firstNonBlank(t, m.vertical(t, 0, if (counted) @intCast(n - 1) else 0, 0)), .lines = true } else return,
            'r' => return replace(ta, i, c),
            'i', 'a' => {
                const r = m.object(t, i, c, first == 'a') orelse return;
                if (o) |op| return self.operate(ta, op, r[0], .{ .pos = r[1] });
                if (r[1] > r[0]) {
                    self.anchor = r[0];
                    self.cur = m.prev(t, r[1]);
                    self.show(ta);
                }
                return;
            },
            else => .{
                .pos = m.find(t, i, c, first == 'f' or first == 't', first == 't' or first == 'T') orelse return,
                .incl = first == 'f' or first == 't',
            },
        };
        if (o) |op| return self.operate(ta, op, i, tg);
        self.go(ta, tg);
        if (self.visual()) self.show(ta);
    }

    fn wantCol(self: *Vim, t: []const u8, i: usize) usize {
        if (i != self.col_at) self.col = i - m.lineStart(t, i);
        return self.col;
    }

    fn go(self: *Vim, ta: *TextAreaState, tg: Target) void {
        const t = ta.getText();
        self.cur = m.clamp(t, tg.pos);
        if (self.visual()) self.show(ta) else ta.select(null, self.cur);
    }

    /// Applies `op` (d / c / y) from `i` to the target.
    fn operate(self: *Vim, ta: *TextAreaState, op: u8, i: usize, tg: Target) void {
        const t = ta.getText();
        var a = @min(i, tg.pos);
        var b = @max(i, tg.pos);
        if (tg.incl) b = m.next(t, b);
        if (tg.lines) {
            a = m.lineStart(t, a);
            b = m.lineEnd(t, b);
        }
        self.yank(ta, t[a..b], tg.lines);
        // Linewise d takes the newline too (the one before, on the last line).
        if (tg.lines and op == 'd') {
            if (b < t.len) b += 1 else if (a > 0) a -= 1;
        }
        self.mode = .normal;
        switch (op) {
            'y' => ta.select(null, m.clamp(t, if (tg.lines) i else a)),
            'c' => {
                cut(ta, a, b);
                self.mode = .insert;
            },
            else => {
                cut(ta, a, b);
                const t2 = ta.getText();
                ta.select(null, m.clamp(t2, if (tg.lines) m.firstNonBlank(t2, @min(a, t2.len)) else a));
            },
        }
    }

    fn visualKey(self: *Vim, ta: *TextAreaState, c: u8) void {
        const lines = self.mode == .visual_line;
        switch (c) {
            'd', 'x', 'c', 's', 'y' => self.operate(ta, switch (c) {
                'x' => 'd',
                's' => 'c',
                else => c,
            }, self.anchor, .{ .pos = self.cur, .lines = lines, .incl = !lines }),
            'o' => {
                std.mem.swap(usize, &self.anchor, &self.cur);
                self.show(ta);
            },
            'v', 'V' => if (lines == (c == 'V')) {
                self.mode = .normal;
                ta.select(null, self.cur);
            } else self.startVisual(self.anchor, if (c == 'V') .visual_line else .visual),
            else => {},
        }
        if (self.visual()) self.show(ta);
    }

    fn startVisual(self: *Vim, i: usize, mode: Mode) void {
        if (!self.visual()) {
            self.anchor = i;
            self.cur = i;
        }
        self.mode = mode;
    }

    /// Selects the visual range, inclusive of the character under the cursor.
    fn show(self: *Vim, ta: *TextAreaState) void {
        const t = ta.getText();
        const lo = @min(self.anchor, self.cur);
        const hi = @max(self.anchor, self.cur);
        const a = if (self.mode == .visual_line) m.lineStart(t, lo) else lo;
        const b = if (self.mode == .visual_line) m.lineEnd(t, hi) else m.next(t, hi);
        if (self.cur >= self.anchor) ta.select(a, b) else ta.select(b, a);
    }

    fn insert(self: *Vim, ta: *TextAreaState, i: usize) void {
        ta.select(null, i);
        self.mode = .insert;
    }

    /// `o` / `O`: a new line below / above, with this line's indent.
    fn openLine(self: *Vim, ta: *TextAreaState, i: usize, below: bool) void {
        const t = ta.getText();
        var buf: [256]u8 = undefined;
        const indent = t[m.lineStart(t, i)..m.firstNonBlank(t, i)];
        const n = @min(indent.len, buf.len - 1);
        if (below) {
            buf[0] = '\n';
            @memcpy(buf[1 .. n + 1], indent[0..n]);
            ta.select(null, m.lineEnd(t, i));
            ta.insertText(buf[0 .. n + 1]) catch {};
        } else {
            const s = m.lineStart(t, i);
            @memcpy(buf[0..n], indent[0..n]);
            buf[n] = '\n';
            ta.select(null, s);
            ta.insertText(buf[0 .. n + 1]) catch {};
            ta.select(null, s + n);
        }
        self.mode = .insert;
    }

    fn yank(self: *Vim, ta: *TextAreaState, text: []const u8, lines: bool) void {
        self.reg.clearRetainingCapacity();
        self.reg.appendSlice(std.heap.page_allocator, text) catch return;
        if (lines) self.reg.append(std.heap.page_allocator, '\n') catch {};
        self.reg_lines = lines;
        // The editor's ⌘C copies its selection to the clipboard.
        const t = ta.getText();
        const start = @intFromPtr(text.ptr) - @intFromPtr(t.ptr);
        ta.select(start, start + text.len);
        press(ta, .c, .{ .cmd = true });
        ta.select(null, start);
    }

    /// `p` / `P`: the register after / before the cursor (below / above for lines).
    fn paste(self: *Vim, ta: *TextAreaState, i: usize, after: bool, n: usize) void {
        if (self.reg.items.len == 0) return;
        const t = ta.getText();
        var pos = if (!after) i else if (self.reg_lines) m.lineEnd(t, i) else @min(m.next(t, i), m.lineEnd(t, i));
        if (self.reg_lines) {
            if (!after) pos = m.lineStart(t, i) else if (pos < t.len) pos += 1 else {
                ta.select(null, pos);
                ta.insertText("\n") catch {};
                pos += 1;
            }
        }
        ta.select(null, pos);
        for (0..n) |_| ta.insertText(self.reg.items) catch {};
        const t2 = ta.getText();
        ta.select(null, if (self.reg_lines) m.firstNonBlank(t2, pos) else m.prev(t2, ta.cursor_byte));
    }

    fn toggleCase(_: *Vim, ta: *TextAreaState, i: usize) void {
        const t = ta.getText();
        if (i >= m.lineEnd(t, i)) return;
        const c = t[i];
        const swapped = if (std.ascii.isUpper(c)) std.ascii.toLower(c) else std.ascii.toUpper(c);
        if (swapped != c) replace(ta, i, swapped);
        ta.select(null, m.right(ta.getText(), i));
    }
};

fn replace(ta: *TextAreaState, i: usize, c: u8) void {
    const t = ta.getText();
    if (i >= m.lineEnd(t, i) or c < ' ') return;
    ta.select(i, m.next(t, i));
    ta.insertText(&.{c}) catch {};
    ta.select(null, i);
}

/// `J`: joins the next line onto this one with a single space.
fn join(ta: *TextAreaState) void {
    const t = ta.getText();
    const e = m.lineEnd(t, ta.cursor_byte);
    if (e == t.len) return;
    ta.select(e, m.firstNonBlank(t, e + 1));
    ta.insertText(" ") catch {};
    ta.select(null, e);
}

fn cut(ta: *TextAreaState, a: usize, b: usize) void {
    if (a == b) return ta.select(null, a);
    ta.select(a, b);
    press(ta, .forward_delete, .{});
}

fn press(ta: *TextAreaState, key: KeyCode, mods: Modifiers) void {
    ta.handleKey(.{ .key = key, .modifiers = mods, .characters = null, .characters_ignoring_modifiers = null, .is_repeat = false }) catch {};
}

fn rep(f: *const fn ([]const u8, usize) usize, t: []const u8, i: usize, n: usize) usize {
    var j = i;
    for (0..n) |_| j = f(t, j);
    return j;
}

fn repDir(f: *const fn ([]const u8, usize, bool) usize, t: []const u8, i: usize, n: usize, forward: bool) usize {
    var j = i;
    for (0..n) |_| j = f(t, j, forward);
    return j;
}
