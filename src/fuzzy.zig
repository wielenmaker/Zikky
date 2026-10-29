//! Fuzzy matching for quick open: the query's letters must appear in order
//! (any case). Letters starting a word or the file name, and runs of
//! consecutive letters, score higher; shorter paths win ties.

const std = @import("std");

/// The match's score, or null when `query` is not a subsequence of `text`.
pub fn score(text: []const u8, query: []const u8) ?i32 {
    var buf: [256]u16 = undefined;
    const at = positions(text, query, &buf) orelse return null;
    const name_start = if (std.mem.lastIndexOfScalar(u8, text, '/')) |i| i + 1 else 0;
    var total: i32 = -@as(i32, @intCast(@min(text.len, 200)));
    for (at, 0..) |p, k| {
        total += 10;
        if (p >= name_start) total += 8;
        if (p == 0 or isBoundary(text, p)) total += 12;
        if (k > 0 and at[k - 1] + 1 == p) total += 15;
    }
    return total;
}

/// Where the query's letters match: each at the earliest place after the
/// previous one, preferring a word start within the file name. Null if absent.
pub fn positions(text: []const u8, query: []const u8, out: []u16) ?[]u16 {
    if (query.len > out.len or text.len > std.math.maxInt(u16)) return null;
    const name_start = if (std.mem.lastIndexOfScalar(u8, text, '/')) |i| i + 1 else 0;
    // Start in the file name when all of the query fits there.
    const from: usize = if (subsequence(text[name_start..], query)) name_start else 0;
    var i = from;
    for (query, 0..) |q, k| {
        while (i < text.len and std.ascii.toLower(text[i]) != std.ascii.toLower(q)) i += 1;
        if (i == text.len) return null;
        out[k] = @intCast(i);
        i += 1;
    }
    return out[0..query.len];
}

fn subsequence(text: []const u8, query: []const u8) bool {
    var i: usize = 0;
    for (query) |q| {
        while (i < text.len and std.ascii.toLower(text[i]) != std.ascii.toLower(q)) i += 1;
        if (i == text.len) return false;
        i += 1;
    }
    return true;
}

fn isBoundary(text: []const u8, p: usize) bool {
    const prev = text[p - 1];
    return prev == '/' or prev == '_' or prev == '-' or prev == '.' or prev == ' ' or
        (std.ascii.isLower(prev) and std.ascii.isUpper(text[p]));
}

test "fuzzy" {
    try std.testing.expect(score("src/state.zig", "stz") != null);
    try std.testing.expect(score("src/state.zig", "zts") == null);
    // The file name beats a scattered match through the folders.
    try std.testing.expect(score("src/main.zig", "main").? > score("vendor/mainline/x/a.zig", "main").?);
    var buf: [8]u16 = undefined;
    try std.testing.expectEqualSlices(u16, &.{ 4, 5 }, positions("src/st.zig", "st", &buf).?);
}
