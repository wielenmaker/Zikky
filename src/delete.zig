//! The row menu's Delete: after a confirm, the file or folder goes to the
//! Trash and the tabs showing it close.

const std = @import("std");
const gooey = @import("gooey");
const tabs = @import("tabs.zig");
const AppState = @import("state.zig").AppState;
const workspace = @import("workspace.zig");
const tab_actions = @import("tab_actions.zig");

const mac = gooey.platform.macos;

/// Runs a nested event loop (the alert), so call it after input handling.
pub fn run(s: *AppState, g: *gooey.Window, node: u32) void {
    var title: [std.fs.max_path_bytes]u8 = undefined;
    const message = std.fmt.bufPrintSentinel(&title, "Do you want to move {s} to the Trash?", .{s.names[node]}, 0) catch return;
    const folder = s.tree.nodes[node].is_folder;
    const info = if (folder) "It and everything in it will move. You can restore them from the Trash." else "You can restore it from the Trash.";
    if ((mac.alert.ask(message, info, &.{ "Move to Trash", "Cancel" }) orelse 1) != 0) return;
    var path: [std.fs.max_path_bytes]u8 = undefined;
    if (!mac.trash.move(std.fmt.bufPrintSentinel(&path, "{s}", .{s.paths[node]}, 0) catch return)) return;
    const rel = s.relativePath(node);
    var i = s.tabs.count;
    while (i > 0) : (i -= 1) {
        const t = s.tabs.list[i - 1];
        if (t.node == tabs.untitled) continue;
        const other = s.relativePath(t.node);
        if (t.node == node or (std.mem.startsWith(u8, other, rel) and other.len > rel.len and other[rel.len] == '/')) tab_actions.drop(s, g, @intCast(i - 1));
    }
    workspace.refresh(s, g, "", "");
}
