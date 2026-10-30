//! A shortcut's keys as text: "cmd-shift-o", the keymap's form, as saved in
//! settings.json; several are separated by spaces. Shown as "⇧⌘" and "O".

const std = @import("std");
const gooey = @import("gooey");

const KeyCode = gooey.input.KeyCode;
const Modifiers = gooey.input.Modifiers;

/// Keys a shortcut can use beside letters and digits, with what they type.
const named = std.StaticStringMap(u8).initComptime(.{
    .{ "equal", '=' }, .{ "minus", '-' }, .{ "backslash", '\\' }, .{ "comma", ',' }, .{ "grave", '`' },
});

/// One-character strings, so labels and menu keys need no buffer.
const chars = blk: {
    var t: [128][1:0]u8 = undefined;
    for (&t, 0..) |*c, i| c.* = .{i};
    break :blk t;
};

/// ⌃⌥⇧⌘ for each set of modifiers (ctrl 1, alt 2, shift 4, cmd 8).
const glyphs = blk: {
    var t: [16][]const u8 = undefined;
    for (&t, 0..) |*g, i| g.* = (if (i & 1 != 0) "⌃" else "") ++ (if (i & 2 != 0) "⌥" else "") ++
        (if (i & 4 != 0) "⇧" else "") ++ (if (i & 8 != 0) "⌘" else "");
    break :blk t;
};

/// What the key named `name` types; null for one a shortcut can't use.
fn char(name: []const u8) ?u8 {
    return if (name.len == 1) name[0] else named.get(name);
}

/// The key's name in a combo ("o" in "cmd-shift-o").
fn key(c: []const u8) []const u8 {
    return c[(std.mem.lastIndexOfScalar(u8, c, '-') orelse return c) + 1 ..];
}

fn has(c: []const u8, mod: []const u8) bool {
    return std.mem.indexOf(u8, c, mod) != null;
}

/// The first of several combos.
pub fn first(keys: []const u8) []const u8 {
    var it = std.mem.tokenizeScalar(u8, keys, ' ');
    return it.next() orelse "";
}

pub fn contains(keys: []const u8, c: []const u8) bool {
    var it = std.mem.tokenizeScalar(u8, keys, ' ');
    while (it.next()) |k| if (std.mem.eql(u8, k, c)) return true;
    return false;
}

/// The key as AppKit's key equivalent: "o", "=".
pub fn keyChar(c: []const u8) [:0]const u8 {
    return &chars[char(key(c)) orelse return ""];
}

/// The key as shown: "O", "=".
pub fn keyLabel(c: []const u8) []const u8 {
    return &chars[std.ascii.toUpper(char(key(c)) orelse return "")];
}

/// The modifiers as shown: "⇧⌘".
pub fn modsLabel(c: []const u8) []const u8 {
    const i = @as(u4, @intFromBool(has(c, "ctrl-"))) | @as(u4, @intFromBool(has(c, "alt-"))) << 1 |
        @as(u4, @intFromBool(has(c, "shift-"))) << 2 | @as(u4, @intFromBool(has(c, "cmd-"))) << 3;
    return glyphs[i];
}

/// A pressed key as a combo; null without ⌘, ⌃ or ⌥, or for a key a shortcut can't use.
pub fn fromEvent(buf: []u8, code: KeyCode, m: Modifiers) ?[]const u8 {
    const name = std.enums.tagName(KeyCode, code) orelse return null;
    if (char(name) == null or !(m.cmd or m.ctrl or m.alt)) return null;
    return std.fmt.bufPrint(buf, "{s}{s}{s}{s}{s}", .{
        if (m.ctrl) "ctrl-" else "",
        if (m.alt) "alt-" else "",
        if (m.shift) "shift-" else "",
        if (m.cmd) "cmd-" else "",
        name,
    }) catch null;
}

test "combo" {
    var buf: [32]u8 = undefined;
    const c = fromEvent(&buf, .o, .{ .cmd = true, .shift = true }).?;
    try std.testing.expectEqualStrings("shift-cmd-o", c);
    try std.testing.expectEqualStrings("⇧⌘", modsLabel(c));
    try std.testing.expectEqualStrings("O", keyLabel(c));
    try std.testing.expectEqualStrings("=", keyLabel("cmd-equal"));
    try std.testing.expect(fromEvent(&buf, .o, .{ .shift = true }) == null);
    try std.testing.expect(contains("cmd-o cmd-p", "cmd-p"));
    try std.testing.expectEqualStrings("cmd-o", first("cmd-o cmd-p"));
}
