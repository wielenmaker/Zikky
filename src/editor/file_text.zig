//! Reads a file for showing as text: its bytes, or why it can't be shown.

const std = @import("std");

const max_bytes = 1 << 20;

pub const Text = struct {
    /// Owned by `std.heap.page_allocator`; empty when `message` says why.
    bytes: []const u8 = "",
    message: []const u8 = "",
};

pub fn read(io: std.Io, path: []const u8) Text {
    const a = std.heap.page_allocator;
    const bytes = std.Io.Dir.readFileAlloc(.cwd(), io, path, a, .limited(max_bytes)) catch |err| {
        return .{ .message = if (err == error.StreamTooLong) "File is too large to open" else "Couldn't read this file" };
    };
    if (!std.unicode.utf8ValidateSlice(bytes)) {
        a.free(bytes);
        return .{ .message = "Binary files can't be shown" };
    }
    return .{ .bytes = bytes };
}
