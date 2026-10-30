//! The command palette (⌘⇧P): the commands, filtered by a fuzzy query as you
//! type. Enter runs one, or shows its submenu in place of the list (Esc goes
//! back, then closes). Its keys come through `Window.key_capture` (`keys.zig`),
//! so the query field keeps typing and vim stays out.

const std = @import("std");
const gooey = @import("gooey");
const AppState = @import("../state.zig").AppState;
const commands = @import("commands.zig");
const fuzzy = @import("fuzzy.zig");
const find = @import("../editor/find.zig");
const picker = @import("picker.zig");

const Command = commands.Command;

pub const row_height: f32 = 28;
pub const query_id = "palette-query";

pub const Open = struct {};

pub const Palette = struct {
    open: bool = false,
    query: []const u8 = "",
    /// The command whose submenu replaces the list.
    sub: ?*const Command = null,
    /// The query and submenu `matches` was built for.
    seen: [128]u8 = undefined,
    seen_len: usize = std.math.maxInt(usize),
    matches: [commands.root.len]u8 = undefined,
    count: u32 = 0,
    selected: u32 = 0,
    list: gooey.widgets.UniformListState = gooey.widgets.UniformListState.init(0, row_height),
    /// The query field takes focus once it exists.
    focus_query: bool = false,

    fn all(self: *const Palette) []const Command {
        return if (self.sub) |c| c.children else &commands.root;
    }

    pub fn at(self: *const Palette, i: u32) *const Command {
        return &self.all()[self.matches[i]];
    }
};

pub fn bindKeys(g: *gooey.Window) void {
    g.keymap().bind(Open, "cmd-shift-p", null);
}

/// ⌘⇧P: opens the palette, or closes it when it shows.
pub fn toggle(s: *AppState, g: *gooey.Window) void {
    if (s.palette.open) return close(s, g);
    if (s.picker.open) picker.close(s, g);
    find.close(s, g);
    reset(&s.palette);
    s.palette.open = true;
    s.palette.focus_query = true;
}

pub fn close(s: *AppState, g: *gooey.Window) void {
    s.palette.open = false;
    s.tabs.focus = true;
    g.requestRender();
}

fn reset(p: *Palette) void {
    p.sub = null;
    p.query = "";
    p.seen_len = std.math.maxInt(usize);
}

/// Rebuilds the matches when the query or the submenu changed; called each frame it shows.
pub fn refresh(s: *AppState) void {
    const p = &s.palette;
    if (p.seen_len == p.query.len and std.mem.eql(u8, p.seen[0..p.seen_len], p.query)) return;
    const q = p.query[0..@min(p.query.len, p.seen.len)];
    @memcpy(p.seen[0..q.len], q);
    p.seen_len = q.len;

    var scores: [commands.root.len]i32 = undefined;
    p.count = 0;
    for (p.all(), 0..) |c, i| {
        scores[i] = if (q.len == 0) 0 else fuzzy.score(c.title, q) orelse continue;
        p.matches[p.count] = @intCast(i);
        p.count += 1;
    }
    // Best first; ties keep the list's order.
    std.sort.pdq(u8, p.matches[0..p.count], @as([]const i32, scores[0..]), struct {
        fn lessThan(sc: []const i32, a: u8, b: u8) bool {
            return if (sc[a] != sc[b]) sc[a] > sc[b] else a < b;
        }
    }.lessThan);
    p.list.setItemCount(p.count);
    select(p, 0);
}

fn select(p: *Palette, i: u32) void {
    p.selected = i;
    if (p.count > 0) p.list.scrollToItem(i, .nearest);
}

/// Runs the command, or shows its submenu.
pub fn pick(s: *AppState, g: *gooey.Window, i: u32) void {
    const p = &s.palette;
    if (i >= p.count) return;
    const c = p.at(i);
    if (c.children.len > 0) {
        reset(p);
        p.sub = c;
        p.focus_query = true;
        return;
    }
    const run = c.run orelse return;
    close(s, g);
    run(s, g);
}

/// Esc in a submenu: back to the commands.
pub fn back(s: *AppState, _: *gooey.Window) void {
    reset(&s.palette);
    s.palette.focus_query = true;
}

/// Its part of `Window.key_capture` while open: moves, runs and closes; the rest types.
pub fn capture(g: *gooey.Window, event: gooey.input.InputEvent) bool {
    const k = switch (event) {
        .key_down => |k| k,
        else => return false,
    };
    const s = g.getRootState(AppState) orelse return false;
    const p = &s.palette;
    const ctrl = k.modifiers.ctrl;
    switch (k.key) {
        .up => select(p, p.selected -| 1),
        .down => select(p, @min(p.selected + 1, p.count -| 1)),
        .p => if (ctrl) select(p, p.selected -| 1) else return false,
        .n => if (ctrl) select(p, @min(p.selected + 1, p.count -| 1)) else return false,
        .@"return" => pick(s, g, p.selected),
        .escape => if (p.sub != null) back(s, g) else close(s, g),
        else => return false,
    }
    g.requestRender();
    return true;
}
