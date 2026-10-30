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
const fs_tree = @import("../tree/fs_tree.zig");
const session = @import("../session.zig");

const max_nodes = gooey.widgets.tree_list.MAX_TREE_NODES;
const CodeEditorState = gooey.widgets.CodeEditorState;

pub const row_height: f32 = 26;

const Match = struct { file: u32, score: i32 };

pub const Picker = struct {
    open: bool = false,
    query: []const u8 = "",
    /// The query `matches` was built for.
    seen: [128]u8 = undefined,
    seen_len: usize = std.math.maxInt(usize),
    /// Files in the folder as paths from it, read from disk on open: the tree
    /// holds only the folders shown. `files` live in `arena`.
    files: [max_nodes][]const u8 = undefined,
    arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator),
    matches: [max_nodes]Match = undefined,
    count: u32 = 0,
    /// Files in the folder, for the n/total count.
    total: u32 = 0,
    selected: u32 = 0,
    list: gooey.widgets.UniformListState = gooey.widgets.UniformListState.init(0, row_height),
    /// The previewed file and its text (or why there is none).
    shown: ?u32 = null,
    preview: file_text.Text = .{},
    /// The preview editor holds `preview`'s text.
    loaded: bool = false,
    /// The query field takes focus once it exists.
    focus_query: bool = false,

    pub fn path(self: *const Picker, i: u32) []const u8 {
        return self.files[self.matches[i].file];
    }

    pub fn shownName(self: *const Picker) []const u8 {
        return if (self.shown) |f| std.fs.path.basename(self.files[f]) else "";
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
    scan(s, g.io);
}

/// Reads the folder's files into `files`, shallowest first, so a big folder
/// deep down can't crowd out the rest when there are more than fit.
fn scan(s: *AppState, io: std.Io) void {
    const p = &s.picker;
    _ = p.arena.reset(.retain_capacity);
    const a = p.arena.allocator();
    p.total = 0;
    if (s.noFolder()) return;
    var dirs: std.ArrayList([]const u8) = .empty;
    dirs.append(a, "") catch return;
    var i: usize = 0;
    while (i < dirs.items.len) : (i += 1) {
        const rel = dirs.items[i];
        const full = if (rel.len == 0) s.root else std.fs.path.join(a, &.{ s.root, rel }) catch return;
        var dir = std.Io.Dir.openDir(.cwd(), io, full, .{ .iterate = true }) catch continue;
        defer dir.close(io);
        var it = dir.iterate();
        while (it.next(io) catch null) |e| {
            if (fs_tree.skips(s, e.name)) continue;
            const file = (if (rel.len == 0) a.dupe(u8, e.name) else std.fs.path.join(a, &.{ rel, e.name })) catch return;
            if (e.kind == .directory) {
                dirs.append(a, file) catch return;
                continue;
            }
            if (p.total == max_nodes) return;
            p.files[p.total] = file;
            p.total += 1;
        }
    }
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
    for (p.files[0..p.total], 0..) |file, f| {
        const sc = if (q.len == 0) 0 else fuzzy.score(file, q) orelse continue;
        p.matches[p.count] = .{ .file = @intCast(f), .score = sc };
        p.count += 1;
    }
    // Best first; ties keep the scan's order.
    std.sort.pdq(Match, p.matches[0..p.count], {}, struct {
        fn lessThan(_: void, a: Match, b: Match) bool {
            return if (a.score != b.score) a.score > b.score else a.file < b.file;
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
    setPreview(s, g, p.matches[i].file);
}

/// Loads `file` into the preview editor, freeing the last one.
fn setPreview(s: *AppState, g: *gooey.Window, file: ?u32) void {
    // Closing empties the preview editor too (it keeps its state).
    defer if (file == null) loadPreview(s, g);
    const p = &s.picker;
    if (p.shown == file) return;
    if (p.preview.bytes.len > 0) std.heap.page_allocator.free(p.preview.bytes);
    p.shown = file;
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    const full = if (file) |f| std.fmt.bufPrint(&buf, "{s}/{s}", .{ s.root, p.files[f] }) catch "" else "";
    p.preview = if (file != null) file_text.read(g.io, full) else .{};
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
    const n = session.find(s, g.io, s.picker.path(i));
    close(s, g);
    tab_actions.open(s, g, n orelse return);
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
    return if (s.picker.shown != null) syntax.forName(s.picker.shownName()) else null;
}
