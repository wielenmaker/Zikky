//! User settings, kept in settings.json and changed from the settings page (⌘,).

const std = @import("std");

pub const Settings = struct {
    /// An `editor_font.families` name.
    font: []const u8 = "JetBrains Mono Nerd Font",
    font_size: f32 = 13,
    appearance: Appearance = .system,
    vim_mode: bool = true,
    soft_wrap: bool = true,
    line_numbers: bool = true,
    smooth_caret: bool = true,
    show_hidden: bool = false,
    /// Comma-separated folder names the tree skips.
    exclude: []const u8 = ".git, .zig-cache, node_modules, target, zig-out, zig-pkg",
    restore_session: bool = true,

    pub const file = "settings.json";

    pub const Appearance = enum { system, light, dark };

    /// The settings shown as toggles.
    pub const Switch = enum { vim_mode, soft_wrap, line_numbers, smooth_caret, show_hidden, restore_session };

    pub fn get(self: *const Settings, sw: Switch) bool {
        return switch (sw) {
            inline else => |t| @field(self, @tagName(t)),
        };
    }

    pub fn flip(self: *Settings, sw: Switch) void {
        switch (sw) {
            inline else => |t| @field(self, @tagName(t)) = !@field(self, @tagName(t)),
        }
    }

    pub fn excludes(self: *const Settings, name: []const u8) bool {
        var it = std.mem.tokenizeScalar(u8, self.exclude, ',');
        while (it.next()) |n| if (std.mem.eql(u8, std.mem.trim(u8, n, " "), name)) return true;
        return false;
    }
};

test "excludes" {
    const s = Settings{};
    try std.testing.expect(s.excludes("zig-out"));
    try std.testing.expect(!s.excludes("src"));
}
