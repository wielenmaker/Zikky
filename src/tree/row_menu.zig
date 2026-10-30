//! The tree's right-click menu: open (here or in a new tab), a new file in a folder,
//! reveal in Finder, copy the path.

const std = @import("std");
const gooey = @import("gooey");
const AppState = @import("../state.zig").AppState;
const tab_actions = @import("../editor/tab_actions.zig");
const rename = @import("rename.zig");
const delete = @import("delete.zig");
const new_file = @import("new_file.zig");

const mac = gooey.platform.macos;

const file_items = [_][:0]const u8{ "Open", "Open in New Tab", "Reveal in Finder", "Copy Path", "Copy Relative Path", "Rename", "Delete" };
const folder_items = [_][:0]const u8{ "New File", "Reveal in Finder", "Copy Path", "Copy Relative Path", "Rename", "Delete" };
/// The opened folder itself stays where it is.
const root_items = [_][:0]const u8{ "New File", "Reveal in Finder", "Copy Path" };

/// Right click, or control-click as macOS treats it.
pub fn isMenuClick(g: *gooey.Window) bool {
    return g.mouse_down.button == .right or g.mouse_down.modifiers.ctrl;
}

/// Shows the menu for `node` and runs the picked item. Deferred: the menu
/// runs a nested event loop.
pub fn show(s: *AppState, g: *gooey.Window, node: u32) void {
    const items: []const [:0]const u8 = if (node == 0) &root_items else if (s.tree.nodes[node].is_folder) &folder_items else &file_items;
    const picked = mac.menu.popUp(items) orelse return;
    const item = items[picked];
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    const path = absolute(s, node, &buf) catch return;
    if (std.mem.eql(u8, item, "Open")) {
        tab_actions.open(s, g, node);
    } else if (std.mem.eql(u8, item, "Open in New Tab")) {
        tab_actions.openNew(s, g, node);
    } else if (std.mem.eql(u8, item, "New File")) {
        new_file.run(s, g, node);
    } else if (std.mem.eql(u8, item, "Reveal in Finder")) {
        reveal(g.io, path);
    } else if (std.mem.eql(u8, item, "Copy Path")) {
        _ = mac.clipboard.setText(path);
    } else if (std.mem.eql(u8, item, "Copy Relative Path")) {
        _ = mac.clipboard.setText(s.relativePath(node));
    } else if (std.mem.eql(u8, item, "Rename")) {
        rename.start(s, g, node);
    } else {
        delete.run(s, g, node);
    }
}

fn reveal(io: std.Io, path: []const u8) void {
    const a = std.heap.page_allocator;
    const r = std.process.run(a, io, .{ .argv = &.{ "/usr/bin/open", "-R", path } }) catch return;
    a.free(r.stdout);
    a.free(r.stderr);
}

/// Node 0 is the opened folder with its full path.
fn absolute(s: *const AppState, node: u32, buf: []u8) ![]const u8 {
    const rel = s.relativePath(node);
    if (std.mem.eql(u8, rel, ".")) return s.paths[0];
    return std.fmt.bufPrint(buf, "{s}/{s}", .{ s.paths[0], rel });
}
