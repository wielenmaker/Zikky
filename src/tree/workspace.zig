//! The opened folder: loading it into the tree, switching folders, the
//! editor-only window with none open, and rebuilding the tree after files change.

const std = @import("std");
const gooey = @import("gooey");
const fs_tree = @import("fs_tree.zig");
const tabs = @import("../editor/tabs.zig");
const terminal = @import("../terminal/terminal.zig");
const session = @import("../session.zig");
const state = @import("../state.zig");

const AppState = state.AppState;

/// The opened folder is the tree's one root, expanded, with its contents under it.
pub fn load(s: *AppState, io: std.Io) void {
    if (s.noFolder()) return;
    const full = std.Io.Dir.realPathFileAlloc(.cwd(), io, s.root, s.arena) catch s.root;
    const top = s.add(null, std.fs.path.basename(full), full, true) orelse return;
    fs_tree.expand(s, io, top);
    s.tree.rebuild();
}

/// The sidebar's +: picks a folder and shows it in place of the current one. The
/// panel runs a nested event loop, so it waits until the click is handled.
pub fn openFolder(_: *AppState, g: *gooey.Window) void {
    g.deferCommand(promptFolder);
}

fn promptFolder(s: *AppState, g: *gooey.Window) void {
    const picked = gooey.file_dialog.promptForPaths(s.arena, .{ .directories = true, .files = false, .prompt = "Open" }) orelse return;
    defer picked.deinit();
    if (picked.paths.len == 0) return;
    openRoot(s, g, s.arena.dupe(u8, picked.paths[0]) catch return);
}

/// With no folder open: just the editor, on an Untitled tab, the sidebar shut.
pub fn untitled(s: *AppState, g: *gooey.Window) void {
    s.sidebar_open = false;
    s.tabs.current = s.tabs.add(g, tabs.untitled, "") orelse return;
    s.tabs.focus = true;
}

/// The sidebar asked for with no folder open. Deferred: the alert runs a nested event loop.
pub fn askFolder(s: *AppState, g: *gooey.Window) void {
    const alert = gooey.platform.macos.alert;
    if (alert.ask("Open a folder first", "The sidebar shows the files of an open folder.", &.{ "Open Folder…", "Cancel" }) == 0) promptFolder(s, g);
}

/// Shows `path` in the tree in place of the current folder. Coming from no
/// folder, the Untitled tabs stay.
pub fn openRoot(s: *AppState, g: *gooey.Window, path: []const u8) void {
    if (!s.noFolder()) closeAll(s, g);
    s.root = path;
    s.sidebar_open = true;
    s.tree.clear();
    load(s, g.io);
}

/// Rebuilds the tree after a setting that filters it changed.
pub fn reload(s: *AppState, g: *gooey.Window) void {
    s.tree.clear();
    load(s, g.io);
    closeAll(s, g);
}

/// Rebuilds the tree after files were created, renamed or removed, keeping the expanded
/// folders and the open tabs. `from` (a path from the opened folder) was renamed to `to`;
/// "" when nothing was.
pub fn refresh(s: *AppState, g: *gooey.Window, from: []const u8, to: []const u8) void {
    const a = std.heap.page_allocator;
    var open: [tabs.max][]const u8 = undefined;
    for (s.tabs.items(), 0..) |t, i| open[i] = if (t.node == tabs.untitled) "" else moved(s, s.relativePath(t.node), from, to);
    var expanded: std.ArrayList([]const u8) = .empty;
    defer expanded.deinit(a);
    for (1..s.tree.node_count) |n| {
        const node: u32 = @intCast(n);
        if (s.tree.nodes[node].is_folder and s.tree.isExpanded(node)) expanded.append(a, moved(s, s.relativePath(node), from, to)) catch {};
    }
    s.tree.clear();
    load(s, g.io);
    for (expanded.items) |e| if (fs_tree.find(s, g.io, e)) |n| fs_tree.expand(s, g.io, n);
    s.tree.rebuild();
    for (s.tabs.items(), open[0..s.tabs.count]) |*t, rel| {
        if (t.node != tabs.untitled) t.node = session.find(s, g.io, rel) orelse 0;
    }
}

/// `rel` once `from` is renamed to `to`: what is under it moves along.
fn moved(s: *AppState, rel: []const u8, from: []const u8, to: []const u8) []const u8 {
    if (from.len == 0 or !std.mem.startsWith(u8, rel, from)) return rel;
    const rest = rel[from.len..];
    if (rest.len > 0 and rest[0] != '/') return rel;
    return std.fmt.allocPrint(s.arena, "{s}{s}", .{ to, rest }) catch rel;
}

fn closeAll(s: *AppState, g: *gooey.Window) void {
    while (s.tabs.count > 0) s.tabs.remove(g, s.tabs.count - 1);
    terminal.end(&s.term.bare);
    s.term.focus = false;
}
