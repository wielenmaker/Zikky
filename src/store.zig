//! Small JSON files in ~/Library/Application Support/Slate (settings, session).

const std = @import("std");

/// Set at start from $HOME; empty disables loading and saving.
pub var dir: []const u8 = "";

/// The file's contents, or `T`'s defaults if it is missing or unreadable.
/// Strings point into `arena`.
pub fn load(comptime T: type, arena: std.mem.Allocator, io: std.Io, name: []const u8) T {
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    const path = std.fmt.bufPrint(&buf, "{s}/{s}", .{ dir, name }) catch return .{};
    const bytes = std.Io.Dir.readFileAlloc(.cwd(), io, path, arena, .limited(1 << 16)) catch return .{};
    return std.json.parseFromSliceLeaky(T, arena, bytes, .{ .ignore_unknown_fields = true }) catch .{};
}

pub fn save(io: std.Io, name: []const u8, value: anytype) void {
    if (dir.len == 0) return;
    const a = std.heap.page_allocator;
    const json = std.json.Stringify.valueAlloc(a, value, .{ .whitespace = .indent_2 }) catch return;
    defer a.free(json);
    std.Io.Dir.createDirPath(.cwd(), io, dir) catch return;
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    const path = std.fmt.bufPrint(&buf, "{s}/{s}", .{ dir, name }) catch return;
    std.Io.Dir.writeFile(.cwd(), io, .{ .sub_path = path, .data = json }) catch {};
}
