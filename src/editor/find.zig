//! Find in the shown file (⌘F; vim's `/` and `?`). Every match of the query
//! is marked and the current one selected; Enter / ⇧Enter, ↑ / ↓ and
//! ⌘G / ⇧⌘G step through them, vim's `n` / `N` too once the bar is closed.
//! Matching ignores case unless the query has a capital (smart case).

const std = @import("std");
const gooey = @import("gooey");
const theme = @import("../theme.zig");
const AppState = @import("../state.zig").AppState;
const tabs = @import("tabs.zig");

const CodeEditorState = gooey.widgets.CodeEditorState;
const Mark = gooey.widgets.text_area_state.Mark;

pub const Open = struct {};
pub const Next = struct {};
pub const Prev = struct {};

pub const query_id = "find-query";
const max_matches = 1 << 16;

pub const Find = struct {
    open: bool = false,
    query: []const u8 = "",
    focus_query: bool = false,
    /// Opened by vim's `/` or `?`: Enter goes to the match and closes, like vim.
    vim: bool = false,
    /// `?`: typing searches upward from where the cursor was.
    backward: bool = false,
    origin: usize = 0,
    matches: [max_matches]Mark = undefined,
    count: usize = 0,
    current: ?usize = null,
    /// What `matches` were found for: the query, the text and its revision.
    seen: [256]u8 = undefined,
    seen_len: usize = std.math.maxInt(usize),
    seen_text: usize = 0,
    seen_revision: u64 = 0,
};

/// The last search, for vim's `n` / `N` and ⌘G once the bar is closed.
var last: [256]u8 = undefined;
var last_len: usize = 0;
var last_backward = false;

pub fn bindKeys(g: *gooey.Window) void {
    g.keymap().bind(Open, "cmd-f", null);
    g.keymap().bind(Next, "cmd-g", null);
    g.keymap().bind(Prev, "cmd-shift-g", null);
}

/// ⌘F: opens the bar, its query the selection if there is one on a line.
pub fn open(s: *AppState, g: *gooey.Window) void {
    const ce = s.editor(g) orelse return;
    if (s.tabs.active() == null) return;
    const ta = &ce.text_area;
    const t = ta.getText();
    if (ta.selection_anchor) |a| {
        const sel = t[@min(a, ta.cursor_byte)..@max(a, ta.cursor_byte)];
        if (sel.len > 0 and sel.len <= 128 and std.mem.indexOfScalar(u8, sel, '\n') == null) s.find.query = sel;
    }
    start(s, g, false, false);
}

/// Vim's `/` (or `?` upward): an empty query.
pub fn openVim(s: *AppState, g: *gooey.Window, backward: bool) void {
    if (s.tabs.active() == null) return;
    s.find.query = "";
    start(s, g, true, backward);
}

fn start(s: *AppState, g: *gooey.Window, from_vim: bool, backward: bool) void {
    const f = &s.find;
    const ce = s.editor(g) orelse return;
    f.open = true;
    f.vim = from_vim;
    f.backward = backward;
    f.origin = if (ce.text_area.selection_anchor) |a| @min(a, ce.text_area.cursor_byte) else ce.text_area.cursor_byte;
    f.seen_len = std.math.maxInt(usize);
    f.focus_query = true;
    // The bar takes the focus, not the editor (a command palette just handed it back).
    s.tabs.focus = false;
    g.requestRender();
}

/// Closes the bar and gives the editor the focus; the current match stays
/// selected (in vim, the cursor goes to its start).
pub fn close(s: *AppState, g: *gooey.Window) void {
    const f = &s.find;
    if (!f.open) return;
    f.open = false;
    remember(f);
    if (s.editor(g)) |ce| if (f.current) |i| if (i < f.count) {
        const m = f.matches[i];
        if (s.settings.vim_mode) ce.text_area.select(null, m.start) else ce.text_area.select(m.start, m.end);
    };
    clearMarks(s, g, null);
    s.tabs.focus = true;
    g.requestRender();
}

/// Vim's Esc: back to where the search started.
fn cancel(s: *AppState, g: *gooey.Window) void {
    s.find.current = null;
    const origin = s.find.origin;
    close(s, g);
    if (s.editor(g)) |ce| ce.text_area.select(null, @min(origin, ce.text_area.getText().len));
}

fn remember(f: *const Find) void {
    if (f.query.len == 0) return;
    last_len = @min(f.query.len, last.len);
    @memcpy(last[0..last_len], f.query[0..last_len]);
    last_backward = f.backward;
}

/// Finds the matches again when the query or the text changed, and marks
/// them in the shown editor; called each frame the bar shows.
pub fn refresh(s: *AppState, g: *gooey.Window) void {
    const f = &s.find;
    const ce = s.editor(g) orelse return;
    clearMarks(s, g, ce);
    const ta = &ce.text_area;
    const text = ta.getText();
    const q = f.query[0..@min(f.query.len, f.seen.len)];
    const query_changed = f.seen_len != q.len or !std.mem.eql(u8, f.seen[0..f.seen_len], q);
    const text_changed = f.seen_text != @intFromPtr(ce) or f.seen_revision != ta.revision;
    if (query_changed or text_changed) {
        @memcpy(f.seen[0..q.len], q);
        f.seen_len = q.len;
        f.seen_text = @intFromPtr(ce);
        f.seen_revision = ta.revision;
        f.count = all(text, q, &f.matches);
        if (query_changed) {
            // As you type, the first match from where the search started.
            f.current = if (f.count == 0) null else nearest(f.matches[0..f.count], f.origin, f.backward);
            if (f.current) |i| ta.select(f.matches[i].start, f.matches[i].end);
        } else if (f.current) |i| {
            f.current = if (f.count == 0) null else @min(i, f.count - 1);
        }
    }
    ta.marks = f.matches[0..f.count];
    ta.mark_color = gooey.scene.Hsla.fromColor(theme.color.syntax.number.withAlpha(if (theme.color.dark) 0.3 else 0.22));
}

/// Marks belong to the shown editor only; the others (hidden tabs) lose them.
fn clearMarks(s: *AppState, g: *gooey.Window, keep: ?*CodeEditorState) void {
    for (s.tabs.items()) |*t| if (tabs.editor(g, t.id())) |ce| {
        if (ce != keep) ce.text_area.marks = &.{};
    };
}

/// Enter / ⌘G (`dir` 1) and ⇧Enter / ⇧⌘G (-1). With the bar closed, from
/// the cursor with the last query.
pub fn step(s: *AppState, g: *gooey.Window, dir: i2) void {
    const f = &s.find;
    const ce = s.editor(g) orelse return;
    const ta = &ce.text_area;
    if (!f.open) {
        // Upward starts before the selected match, not at its end.
        const from = if (dir < 0) @min(ta.selection_anchor orelse ta.cursor_byte, ta.cursor_byte) else ta.cursor_byte;
        const m = nextFrom(ta.getText(), from, dir > 0) orelse return;
        ta.select(m.start, m.end);
        return;
    }
    if (f.count == 0) return;
    const i = f.current orelse 0;
    f.current = if (dir > 0) (i + 1) % f.count else (i + f.count - 1) % f.count;
    const m = f.matches[f.current.?];
    ta.select(m.start, m.end);
    g.requestRender();
}

pub fn next(s: *AppState, g: *gooey.Window) void {
    step(s, g, 1);
}

pub fn prev(s: *AppState, g: *gooey.Window) void {
    step(s, g, -1);
}

/// Its part of `Window.key_capture` while open. With the query focused:
/// Enter, ⇧Enter, ↑ / ↓ step and Esc closes (vim: Enter goes to the match,
/// Esc cancels); the rest types. In the editor, Esc closes it (without vim).
pub fn capture(g: *gooey.Window, event: gooey.input.InputEvent) bool {
    const k = switch (event) {
        .key_down => |k| k,
        else => return false,
    };
    const s = g.getRootState(AppState) orelse return false;
    if (!g.focus.isFocusedByName(query_id)) {
        if (k.key == .escape and !s.settings.vim_mode) {
            close(s, g);
            return true;
        }
        return false;
    }
    switch (k.key) {
        .@"return" => if (s.find.vim) close(s, g) else step(s, g, if (k.modifiers.shift) -1 else 1),
        .escape => if (s.find.vim) cancel(s, g) else close(s, g),
        .up => step(s, g, -1),
        .down => step(s, g, 1),
        else => return false,
    }
    g.requestRender();
    return true;
}

/// The match after `pos` (or before it, upward), wrapping around; vim's `n`.
pub fn nextFrom(text: []const u8, pos: usize, forward: bool) ?Mark {
    const q = last[0..last_len];
    if (q.len == 0) return null;
    const fold = !hasUpper(q);
    // Forward: the first match, for wrapping. Upward: the last before `pos`,
    // else (wrapping) the last of all.
    var first: ?Mark = null;
    var before: ?Mark = null;
    var final: ?Mark = null;
    var i: usize = 0;
    while (find(text, i, q, fold)) |at| : (i = at + 1) {
        const m = Mark{ .start = at, .end = at + q.len };
        if (forward) {
            if (at > pos) return m;
            if (first == null) first = m;
        } else {
            if (at < pos) before = m else if (before != null) return before;
            final = m;
        }
    }
    return if (forward) first else before orelse final;
}

/// Vim's `n` follows the last search's direction, `N` the other.
pub fn vimForward(n_key: bool) bool {
    return n_key != last_backward;
}

/// Every match of `q` in `text`, up to `out.len`; the count.
fn all(text: []const u8, q: []const u8, out: []Mark) usize {
    if (q.len == 0) return 0;
    const fold = !hasUpper(q);
    var n: usize = 0;
    var i: usize = 0;
    while (n < out.len) : (n += 1) {
        const at = find(text, i, q, fold) orelse break;
        out[n] = .{ .start = at, .end = at + q.len };
        i = at + q.len;
    }
    return n;
}

/// The match to show first: at or after `origin` (or the last one before it, upward), wrapping.
fn nearest(ms: []const Mark, origin: usize, backward: bool) usize {
    if (backward) {
        var i = ms.len;
        while (i > 0) : (i -= 1) if (ms[i - 1].start < origin) return i - 1;
        return ms.len - 1;
    }
    for (ms, 0..) |m, i| if (m.start >= origin) return i;
    return 0;
}

fn find(text: []const u8, from: usize, q: []const u8, fold: bool) ?usize {
    if (!fold) return std.mem.indexOfPos(u8, text, from, q);
    if (q.len > text.len) return null;
    const first = std.ascii.toLower(q[0]);
    var i = from;
    while (i + q.len <= text.len) : (i += 1) {
        if (std.ascii.toLower(text[i]) == first and std.ascii.eqlIgnoreCase(text[i..][0..q.len], q)) return i;
    }
    return null;
}

fn hasUpper(q: []const u8) bool {
    for (q) |c| if (std.ascii.isUpper(c)) return true;
    return false;
}

test "smart case and wrapping" {
    var out: [8]Mark = undefined;
    try std.testing.expectEqual(@as(usize, 3), all("Foo foo FOO", "foo", &out));
    try std.testing.expectEqual(@as(usize, 1), all("Foo foo FOO", "Foo", &out));
    const ms = [_]Mark{ .{ .start = 2, .end = 3 }, .{ .start = 8, .end = 9 } };
    try std.testing.expectEqual(@as(usize, 1), nearest(&ms, 5, false));
    try std.testing.expectEqual(@as(usize, 0), nearest(&ms, 9, false));
    try std.testing.expectEqual(@as(usize, 0), nearest(&ms, 5, true));
    try std.testing.expectEqual(@as(usize, 1), nearest(&ms, 1, true));

    @memcpy(last[0..2], "ab");
    last_len = 2;
    try std.testing.expectEqual(@as(usize, 3), nextFrom("ab ab ab", 0, true).?.start);
    try std.testing.expectEqual(@as(usize, 0), nextFrom("ab ab ab", 6, true).?.start);
    try std.testing.expectEqual(@as(usize, 0), nextFrom("ab ab ab", 3, false).?.start);
    try std.testing.expectEqual(@as(usize, 6), nextFrom("ab ab ab", 0, false).?.start);
}
