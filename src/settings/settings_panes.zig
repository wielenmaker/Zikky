//! What the settings page shows: panes of sections of rows, like Rex's.

const std = @import("std");
const gooey = @import("gooey");
const Lucide = @import("gooey-components").Lucide;
const Switch = @import("settings.zig").Settings.Switch;
const shortcuts = @import("../shortcuts/shortcuts.zig");

const Color = gooey.Color;

pub const Control = union(enum) { toggle: Switch, font, font_size, exclude, theme, preview, shortcut: shortcuts.Id };

pub const Row = struct { label: []const u8, control: Control };
/// An empty title shows the group alone.
pub const Section = struct { title: []const u8, rows: []const Row };

pub const Pane = struct {
    name: []const u8,
    icon: []const u8,
    tint: Color,
    sections: []const Section,

    /// The search field keeps panes whose name or a row's label contains `q`.
    pub fn matches(self: *const Pane, q: []const u8) bool {
        if (contains(self.name, q)) return true;
        for (self.sections) |s| for (s.rows) |r| {
            if (contains(r.label, q)) return true;
        };
        return false;
    }
};

fn contains(text: []const u8, q: []const u8) bool {
    var i: usize = 0;
    while (i + q.len <= text.len) : (i += 1) {
        if (std.ascii.startsWithIgnoreCase(text[i..], q)) return true;
    }
    return false;
}

pub const panes = [_]Pane{
    .{ .name = "Appearance", .icon = Lucide.palette, .tint = Color.hex(0xa855f7), .sections = &.{
        .{ .title = "Theme", .rows = &.{.{ .label = "Appearance", .control = .theme }} },
        // The preview's label isn't shown; it lets a search for a theme find the pane.
        .{ .title = "", .rows = &.{.{ .label = "Light Dark System", .control = .preview }} },
        .{ .title = "Text", .rows = &.{
            .{ .label = "Font", .control = .font },
            .{ .label = "Font size", .control = .font_size },
        } },
    } },
    .{ .name = "Editor", .icon = Lucide.square_pen, .tint = Color.hex(0x3b82f6), .sections = &.{
        .{ .title = "Editing", .rows = &.{
            .{ .label = "Vim mode", .control = .{ .toggle = .vim_mode } },
            .{ .label = "Wrap long lines", .control = .{ .toggle = .soft_wrap } },
            .{ .label = "Show line numbers", .control = .{ .toggle = .line_numbers } },
            .{ .label = "Smooth caret", .control = .{ .toggle = .smooth_caret } },
        } },
    } },
    .{ .name = "Files", .icon = Lucide.folder, .tint = Color.hex(0xf59e0b), .sections = &.{
        .{ .title = "File Tree", .rows = &.{
            .{ .label = "Show hidden files", .control = .{ .toggle = .show_hidden } },
            .{ .label = "Excluded folders", .control = .exclude },
        } },
    } },
    .{ .name = "Session", .icon = Lucide.history, .tint = Color.hex(0x22c55e), .sections = &.{
        .{ .title = "Startup", .rows = &.{
            .{ .label = "Reopen the last folder and file", .control = .{ .toggle = .restore_session } },
        } },
    } },
    .{ .name = "Keyboard", .icon = Lucide.keyboard, .tint = Color.hex(0x64748b), .sections = &.{
        .{ .title = "Shortcuts", .rows = &shortcut_rows },
    } },
};

const shortcut_rows = blk: {
    var rows: [shortcuts.all.values.len]Row = undefined;
    for (&rows, std.enums.values(shortcuts.Id)) |*r, id| r.* = .{ .label = shortcuts.all.get(id).title, .control = .{ .shortcut = id } };
    break :blk rows;
};

/// The pane to show: the selected one, or the first the search keeps.
pub fn shown(selected: u8, q: []const u8) u8 {
    if (panes[selected].matches(q)) return selected;
    for (panes, 0..) |p, i| if (p.matches(q)) return @intCast(i);
    return selected;
}
