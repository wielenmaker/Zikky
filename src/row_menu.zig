//! The tree's right-click menu: open (here or in a new tab), reveal in Finder, copy the path.

const std = @import("std");
const gooey = @import("gooey");
const AppState = @import("state.zig").AppState;

const mac = gooey.platform.macos;

const file_items = [_][:0]const u8{ "Open", "Open in New Tab", "Reveal in Finder", "Copy Path", "Copy Relative Path" };
const folder_items = [_][:0]const u8{ "Reveal in Finder", "Copy Path", "Copy Relative Path" };

/// Right click, or control-click as macOS treats it.
pub fn isMenuClick(g: *gooey.Window) bool {
    return g.mouse_down.button == .right or g.mouse_down.modifiers.ctrl;
}

/// Shows the menu for `node` and runs the picked item. Deferred: the menu
/// runs a nested event loop.
pub fn show(s: *AppState, g: *gooey.Window, node: u32) void {
    const folder = s.tree.nodes[node].is_folder;
    const picked = mac.menu.popUp(if (folder) &folder_items else &file_items) orelse return;
    const item = if (folder) folder_items[picked] else file_items[picked];
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    const path = absolute(s, node, &buf) catch return;
    if (std.mem.eql(u8, item, "Open")) {
        s.openNode(g, node);
    } else if (std.mem.eql(u8, item, "Open in New Tab")) {
        s.openInNewTab(g, node);
    } else if (std.mem.eql(u8, item, "Reveal in Finder")) {
        reveal(g.io, path);
    } else if (std.mem.eql(u8, item, "Copy Path")) {
        _ = mac.clipboard.setText(path);
    } else {
        _ = mac.clipboard.setText(s.relativePath(node));
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
