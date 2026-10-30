//! Quick open (⌘O / ⌘P): every file in the opened folder, filtered by a fuzzy
//! query as you type, with the selected one previewed. Its keys come through
//! `Window.key_capture` (`keys.zig`), so the query field keeps typing and vim stays out.

const std = @import("std");
const gooey = @import("gooey");
const AppState = @import("../state.zig").AppState;
const tab_actions = @import("../editor/tab_actions.zig");
const picker = @import("picker.zig");
const fuzzy = @import("fuzzy.zig");
const file_text = @import("../editor/file_text.zig");
const syntax = @import("../syntax/syntax.zig");
const find = @import("../editor/find.zig");
const palette = @import("palette.zig");

const max_nodes = gooey.widgets.tree_list.MAX_TREE_NODES;
const CodeEditorState = gooey.widgets.CodeEditorState;

pub const row_height: f32 = 26;

const Match = struct { node: u32, score: i32 };

pub const Picker = struct {
    open: bool = false,
    query: []const u8 = "",
    /// The query `matches` was built for.
    seen: [128]u8 = undefined,
    seen_len: usize = std.math.maxInt(usize),
    matches: [max_nodes]Match = undefined,
    count: u32 = 0,
    /// Files in the folder, for the n/total count.
    total: u32 = 0,
    selected: u32 = 0,
    list: gooey.widgets.UniformListState = gooey.widgets.UniformListState.init(0, row_height),
    /// The previewed node and its text (or why there is none).
    shown: ?u32 = null,
    preview: file_text.Text = .{},
    /// The preview editor holds `preview`'s text.
    loaded: bool = false,
    /// The query field takes focus once it exists.
    focus_query: bool = false,

    pub fn node(self: *const Picker, i: u32) u32 {
        return self.matches[i].node;
    }
};

/// ⌘O / ⌘P: closes the find bar and the palette first.
pub fn open(s: *AppState, g: *gooey.Window) void {
    find.close(s, g);
    if (s.palette.open) palette.close(s, g);
    const p = &s.picker;
    p.open = true;
    p.query = "";
    p.seen_len = std.math.maxInt(usize);
    p.focus_query = true;
}

pub fn close(s: *AppState, g: *gooey.Window) void {
    s.picker.open = false;
    setPreview(s, g, null);
}

/// Rebuilds the matches when the query changed; called each frame it shows.
pub fn refresh(s: *AppState, g: *gooey.Window) void {
    const p = &s.picker;
    if (p.seen_len == p.query.len and std.mem.eql(u8, p.seen[0..p.seen_len], p.query)) return;
    const q = p.query[0..@min(p.query.len, p.seen.len)];
    @memcpy(p.seen[0..q.len], q);
    p.seen_len = q.len;

    p.count = 0;
    p.total = 0;
    for (1..s.tree.node_count) |n| {
        const id: u32 = @intCast(n);
        if (s.tree.nodes[id].is_folder) continue;
        p.total += 1;
        const sc = if (q.len == 0) 0 else fuzzy.score(s.relativePath(id), q) orelse continue;
        p.matches[p.count] = .{ .node = id, .score = sc };
        p.count += 1;
    }
    // Best first; ties keep the tree's order.
    std.sort.pdq(Match, p.matches[0..p.count], {}, struct {
        fn lessThan(_: void, a: Match, b: Match) bool {
            return if (a.score != b.score) a.score > b.score else a.node < b.node;
        }
    }.lessThan);
    p.list.setItemCount(p.count);
    select(s, g, 0);
}

fn select(s: *AppState, g: *gooey.Window, i: u32) void {
    const p = &s.picker;
    p.selected = i;
    if (p.count == 0) return setPreview(s, g, null);
    p.list.scrollToItem(i, .nearest);
    setPreview(s, g, p.node(i));
}

/// Loads `node` into the preview editor, freeing the last one.
fn setPreview(s: *AppState, g: *gooey.Window, node: ?u32) void {
    // Closing empties the preview editor too (it keeps its state).
    defer if (node == null) loadPreview(s, g);
    const p = &s.picker;
    if (p.shown == node) return;
    if (p.preview.bytes.len > 0) std.heap.page_allocator.free(p.preview.bytes);
    p.shown = node;
    p.preview = if (node) |n| file_text.read(g.io, s.paths[n]) else .{};
    p.loaded = false;
}

/// Puts the preview's text in its editor, once that exists (it is created
/// while rendering, so this runs right after).
pub fn loadPreview(s: *AppState, g: *gooey.Window) void {
    const p = &s.picker;
    if (p.loaded) return;
    const ed = g.widgetState(CodeEditorState, "preview") orelse return;
    ed.setText(p.preview.bytes) catch {};
    ed.text_area.cursor_byte = 0;
    ed.text_area.scroll_offset_y = 0;
    ed.text_area.scroll_target_y = 0;
    p.loaded = true;
}

pub fn pick(s: *AppState, g: *gooey.Window, i: u32) void {
    if (i >= s.picker.count) return;
    const n = s.picker.node(i);
    close(s, g);
    tab_actions.open(s, g, n);
}

/// Its part of `Window.key_capture` while open: moves, opens and closes; the rest types.
pub fn capture(g: *gooey.Window, event: gooey.input.InputEvent) bool {
    const k = switch (event) {
        .key_down => |k| k,
        else => return false,
    };
    const s = g.getRootState(AppState) orelse return false;
    const p = &s.picker;
    const ctrl = k.modifiers.ctrl;
    switch (k.key) {
        .up => select(s, g, p.selected -| 1),
        .down => select(s, g, @min(p.selected + 1, p.count -| 1)),
        .p => if (ctrl) select(s, g, p.selected -| 1) else return false,
        .n => if (ctrl) select(s, g, @min(p.selected + 1, p.count -| 1)) else return false,
        .@"return" => pick(s, g, p.selected),
        .escape => close(s, g),
        else => return false,
    }
    g.requestRender();
    return true;
}

pub fn highlighter(s: *const AppState) ?gooey.widgets.code_editor_state.Highlighter {
    return if (s.picker.shown) |n| syntax.forName(s.names[n]) else null;
}
