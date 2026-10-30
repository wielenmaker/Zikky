//! Vim motions over a buffer: pure functions from a byte offset to a byte offset.

const std = @import("std");

pub fn lineStart(t: []const u8, i: usize) usize {
    return if (std.mem.lastIndexOfScalar(u8, t[0..i], '\n')) |n| n + 1 else 0;
}

pub fn lineEnd(t: []const u8, i: usize) usize {
    return std.mem.indexOfScalarPos(u8, t, i, '\n') orelse t.len;
}

pub fn next(t: []const u8, i: usize) usize {
    var j = @min(i + 1, t.len);
    while (j < t.len and t[j] & 0xc0 == 0x80) j += 1;
    return j;
}

pub fn prev(t: []const u8, i: usize) usize {
    var j = i -| 1;
    while (j > 0 and t[j] & 0xc0 == 0x80) j -= 1;
    return j;
}

/// Normal mode rests on a character, never on a line's newline (unless the line is empty).
pub fn clamp(t: []const u8, i: usize) usize {
    const j = @min(i, t.len);
    return if (j == lineEnd(t, j) and j > lineStart(t, j)) prev(t, j) else j;
}

pub fn left(t: []const u8, i: usize) usize {
    return if (i > lineStart(t, i)) prev(t, i) else i;
}

pub fn right(t: []const u8, i: usize) usize {
    return if (next(t, i) < lineEnd(t, i)) next(t, i) else i;
}

/// `n` lines down (up when negative), at byte column `col` clamped to the line.
pub fn vertical(t: []const u8, i: usize, n: isize, col: usize) usize {
    var s = lineStart(t, i);
    var k = n;
    while (k > 0) : (k -= 1) {
        const e = lineEnd(t, s);
        if (e == t.len) break;
        s = e + 1;
    }
    while (k < 0) : (k += 1) {
        if (s == 0) break;
        s = lineStart(t, s - 1);
    }
    var j = s + @min(col, lineEnd(t, s) - s);
    while (j > s and j < t.len and t[j] & 0xc0 == 0x80) j -= 1;
    return j;
}

pub fn firstNonBlank(t: []const u8, i: usize) usize {
    var j = lineStart(t, i);
    while (j < t.len and (t[j] == ' ' or t[j] == '\t')) j += 1;
    return j;
}

/// 0 blank, 1 word (identifier or non-ASCII), 2 punctuation.
fn class(c: u8) u2 {
    if (std.ascii.isWhitespace(c)) return 0;
    return if (std.ascii.isAlphanumeric(c) or c == '_' or c >= 0x80) 1 else 2;
}

/// `w`: the next word's start; an empty line counts as a word.
pub fn wordForward(t: []const u8, i: usize) usize {
    var j = i;
    if (j < t.len and class(t[j]) != 0) {
        const c = class(t[j]);
        while (j < t.len and class(t[j]) == c) j += 1;
    }
    while (j < t.len and class(t[j]) == 0) : (j += 1) {
        if (t[j] == '\n' and j + 1 < t.len and t[j + 1] == '\n') return j + 1;
    }
    return j;
}

/// `e`: the end of this or the next word.
pub fn wordEnd(t: []const u8, i: usize) usize {
    var j = i + 1;
    while (j < t.len and class(t[j]) == 0) j += 1;
    if (j >= t.len) return i;
    const c = class(t[j]);
    while (j + 1 < t.len and class(t[j + 1]) == c) j += 1;
    return j;
}

/// `b`: the start of this or the previous word.
pub fn wordBack(t: []const u8, i: usize) usize {
    if (i == 0) return 0;
    var j = i - 1;
    while (j > 0 and class(t[j]) == 0) j -= 1;
    const c = class(t[j]);
    while (j > 0 and class(t[j - 1]) == c) j -= 1;
    return j;
}

/// `}` / `{`: the next / previous empty line past the current paragraph.
pub fn paragraph(t: []const u8, i: usize, forward: bool) usize {
    var s = lineStart(t, i);
    var seen = false;
    while (true) {
        const blank = lineEnd(t, s) == s;
        if (blank and seen) return s;
        if (!blank) seen = true;
        if (forward) {
            const e = lineEnd(t, s);
            if (e == t.len) return e;
            s = e + 1;
        } else {
            if (s == 0) return 0;
            s = lineStart(t, s - 1);
        }
    }
}

/// `f` / `F` / `t` / `T`: `c` on the current line; `till` stops one short.
pub fn find(t: []const u8, i: usize, c: u8, forward: bool, till: bool) ?usize {
    if (forward) {
        const j = std.mem.indexOfScalarPos(u8, t[0..lineEnd(t, i)], i + 1, c) orelse return null;
        return if (till) prev(t, j) else j;
    }
    const s = lineStart(t, i);
    const j = s + (std.mem.lastIndexOfScalar(u8, t[s..i], c) orelse return null);
    return if (till) next(t, j) else j;
}

/// Text object `c` (w, quotes, brackets) at `i`, as a byte range; `around` takes the delimiters
/// (for a word, its trailing blanks, or leading ones at a line's end).
pub fn object(t: []const u8, i: usize, c: u8, around: bool) ?[2]usize {
    return switch (c) {
        'w' => word(t, i, around),
        '"', '\'', '`' => quotes(t, i, c, around),
        '(', ')', 'b' => brackets(t, i, '(', ')', around),
        '[', ']' => brackets(t, i, '[', ']', around),
        '{', '}', 'B' => brackets(t, i, '{', '}', around),
        '<', '>' => brackets(t, i, '<', '>', around),
        else => null,
    };
}

fn word(t: []const u8, i: usize, around: bool) ?[2]usize {
    if (i >= t.len or t[i] == '\n') return null;
    const c = class(t[i]);
    var a = i;
    var b = i;
    while (a > 0 and t[a - 1] != '\n' and class(t[a - 1]) == c) a -= 1;
    while (b < t.len and t[b] != '\n' and class(t[b]) == c) b += 1;
    if (around) {
        const e = b;
        while (b < t.len and (t[b] == ' ' or t[b] == '\t')) b += 1;
        if (b == e) while (a > lineStart(t, a) and (t[a - 1] == ' ' or t[a - 1] == '\t')) {
            a -= 1;
        };
    }
    return .{ a, b };
}

/// The pair of `q` on this line around `i`, or the next one after it.
fn quotes(t: []const u8, i: usize, q: u8, around: bool) ?[2]usize {
    var j = lineStart(t, i);
    const e = lineEnd(t, i);
    while (std.mem.indexOfScalarPos(u8, t[0..e], j, q)) |open| {
        const close = std.mem.indexOfScalarPos(u8, t[0..e], open + 1, q) orelse return null;
        if (close >= i) return if (around) .{ open, close + 1 } else .{ open + 1, close };
        j = close + 1;
    }
    return null;
}

/// The innermost `open`…`close` pair enclosing `i` (counting nested pairs).
fn brackets(t: []const u8, i: usize, open: u8, close: u8, around: bool) ?[2]usize {
    if (i >= t.len) return null;
    var a = i;
    var depth: usize = 0;
    while (t[a] != open or depth > 0) {
        if (t[a] == close and a != i) depth += 1;
        if (t[a] == open) depth -= 1;
        if (a == 0) return null;
        a -= 1;
    }
    var b = a + 1;
    depth = 0;
    while (b < t.len and (t[b] != close or depth > 0)) : (b += 1) {
        if (t[b] == open) depth += 1;
        if (t[b] == close) depth -= 1;
    }
    if (b == t.len) return null;
    return if (around) .{ a, b + 1 } else .{ a + 1, b };
}

test "motions" {
    const t = "fn main() {\n    foo_bar(1);\n\nend";
    try std.testing.expectEqual(3, wordForward(t, 0));
    try std.testing.expectEqual(7, wordForward(t, 3));
    try std.testing.expectEqual(16, wordForward(t, 10));
    try std.testing.expectEqual(22, wordEnd(t, 16));
    try std.testing.expectEqual(16, wordBack(t, 23));
    try std.testing.expectEqual(28, wordForward(t, 26));
    try std.testing.expectEqual(16, firstNonBlank(t, 20));
    try std.testing.expectEqual(10, clamp(t, 11));
    try std.testing.expectEqual(14, vertical(t, 2, 1, 2));
    try std.testing.expectEqual(2, vertical(t, 14, -1, 2));
    try std.testing.expectEqual(28, paragraph(t, 0, true));
    try std.testing.expectEqual(25, find(t, 16, ')', true, false).?);
    try std.testing.expectEqual(24, find(t, 16, ')', true, true).?);
    try std.testing.expectEqual([2]usize{ 16, 23 }, object(t, 18, 'w', false).?);
    try std.testing.expectEqual([2]usize{ 2, 7 }, object(t, 5, 'w', true).?);
    try std.testing.expectEqual([2]usize{ 24, 25 }, object(t, 24, '(', false).?);
    try std.testing.expectEqual([2]usize{ 23, 26 }, object(t, 25, 'b', true).?);
    try std.testing.expectEqual([2]usize{ 3, 9 }, object("a { b(c) } d", 6, '{', false).?);
    try std.testing.expectEqual([2]usize{ 3, 6 }, object("a \"xyz\" b", 0, '"', false).?);
}
