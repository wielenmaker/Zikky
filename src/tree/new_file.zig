//! The row menu's New File: an empty `untitled` in the folder, named in place
//! like a rename. Naming it opens it; cancelling removes it.

const std = @import("std");
const gooey = @import("gooey");
const AppState = @import("../state.zig").AppState;
const workspace = @import("workspace.zig");
const fs_tree = @import("fs_tree.zig");
const rename = @import("rename.zig");

pub fn run(s: *AppState, g: *gooey.Window, dir: u32) void {
    const into = s.relativePath(dir);
    const name = create(s, g.io, s.paths[dir]) orelse return;
    workspace.refresh(s, g, "", "");
    const folder = fs_tree.find(s, g.io, into) orelse 0;
    fs_tree.expand(s, g.io, folder);
    s.tree.rebuild();
    const rel = if (folder == 0) name else std.fs.path.join(s.arena, &.{ into, name }) catch return;
    rename.start(s, g, fs_tree.find(s, g.io, rel) orelse return);
    rename.created = true;
}

/// Creates `untitled`, or `untitled 2` and so on when taken; returns its name.
fn create(s: *AppState, io: std.Io, dir: []const u8) ?[]const u8 {
    for (1..100) |i| {
        const name = if (i == 1) "untitled" else std.fmt.allocPrint(s.arena, "untitled {d}", .{i}) catch return null;
        const path = std.fs.path.join(s.arena, &.{ dir, name }) catch return null;
        const file = std.Io.Dir.createFile(.cwd(), io, path, .{ .exclusive = true }) catch |e| switch (e) {
            error.PathAlreadyExists => continue,
            else => return null,
        };
        file.close(io);
        return name;
    }
    return null;
}
