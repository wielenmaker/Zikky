//! Dragging tree rows: a row dropped on a folder (or on a file, into its
//! folder) moves there on disk, and the tabs showing it follow.

const std = @import("std");
const gooey = @import("gooey");
const AppState = @import("../state.zig").AppState;
const workspace = @import("workspace.zig");
const fs_tree = @import("fs_tree.zig");
const theme = @import("../theme.zig");

const ui = gooey.ui;
const Cx = gooey.Cx;
const TreeNode = gooey.widgets.TreeNode;

const mac = gooey.platform.macos;

/// The payload is the dragged row's node, found again by its place in the tree.
pub fn source(s: *AppState, node: u32) ?ui.Draggable {
    return if (node == 0) null else ui.Draggable.init(TreeNode, &s.tree.nodes[node]);
}

/// A drop on `node` lands in it if it is a folder, else in its folder.
pub fn target(cx: *Cx, s: *const AppState, node: u32) ui.DropTarget {
    const n = s.tree.nodes[node];
    const dir = if (n.is_folder) node else n.parent orelse 0;
    return ui.DropTarget.init(TreeNode, cx.commandWith(dir, drop));
}

const Move = struct { node: u32, dir: u32 };

fn drop(s: *AppState, g: *gooey.Window, dir: u32) void {
    const node = dragged(s, g) orelse return;
    // Deferred: a name clash shows an alert, which runs a nested event loop.
    g.deferCommandWith(Move{ .node = node, .dir = dir }, run);
}

fn dragged(s: *const AppState, g: *const gooey.Window) ?u32 {
    const n = (g.getActiveDrag() orelse return null).getValue(TreeNode) orelse return null;
    return @intCast((@intFromPtr(n) - @intFromPtr(&s.tree.nodes[0])) / @sizeOf(TreeNode));
}

fn run(s: *AppState, g: *gooey.Window, m: Move) void {
    const from = s.relativePath(m.node);
    const into = s.relativePath(m.dir);
    // Already there, or into itself.
    if (s.tree.nodes[m.node].parent == m.dir or std.mem.eql(u8, into, from) or within(into, from)) return;
    const name = s.names[m.node];
    const new = std.fs.path.join(s.arena, &.{ s.paths[m.dir], name }) catch return;
    if (std.Io.Dir.access(.cwd(), g.io, new, .{})) |_| return clash(name) else |_| {}
    std.Io.Dir.rename(.cwd(), s.paths[m.node], .cwd(), new, g.io) catch return;
    const to = if (m.dir == 0) name else std.fs.path.join(s.arena, &.{ into, name }) catch return;
    workspace.refresh(s, g, from, to);
    if (fs_tree.find(s, g.io, into)) |d| fs_tree.expand(s, g.io, d);
    s.tree.rebuild();
}

fn within(path: []const u8, dir: []const u8) bool {
    return path.len > dir.len and std.mem.startsWith(u8, path, dir) and path[dir.len] == '/';
}

fn clash(name: []const u8) void {
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    const message = std.fmt.bufPrintSentinel(&buf, "An item named {s} is already there.", .{name}, 0) catch return;
    _ = mac.alert.ask(message, "Rename one of them first.", &.{"OK"});
}

/// The dragged row's name, following the pointer.
pub const Preview = struct {
    pub fn render(_: @This(), cx: *Cx) void {
        const s = cx.stateConst(AppState);
        const node = dragged(s, cx.window()) orelse return;
        const at = cx.window().getActiveDrag().?.cursor_position;
        cx.render(ui.box(.{
            .floating = .{ .attach_to_parent = false, .offset_x = at.x + 12, .offset_y = at.y + 4, .z_index = 1000 },
            .pointer_events = .none,
            .background = theme.color.background,
            .border_width = .{ .all = 1 },
            .border_color = theme.color.border,
            .corner_radius = theme.radius,
            .padding = .{ .symmetric = .{ .x = 8, .y = 3 } },
            .shadow = theme.shadow_xs,
        }, .{ui.text(s.names[node], .{ .size = 13, .color = theme.color.foreground })}));
    }
};
