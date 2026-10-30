//! The editor's font and size: JetBrains Mono Nerd Font (embedded) by default,
//! or SF Mono or Menlo. ⌘+ / ⌘− step the size, ⌘0
//! resets it; both are saved as settings.

const std = @import("std");
const gooey = @import("gooey");
const assets = @import("assets");
const theme = @import("../theme.zig");

const TextSystem = gooey.text.TextSystem;

pub const ZoomIn = struct {};
pub const ZoomOut = struct {};
pub const ZoomReset = struct {};

pub const min_size: f32 = 8;
pub const max_size: f32 = 32;

pub const Family = struct {
    name: [:0]const u8,
    /// Font file bytes, for an embedded face.
    data: ?[]const u8 = null,
    /// Otherwise the face's CoreText name.
    system: []const u8 = "",
};

pub const families = [_]Family{
    .{ .name = "JetBrains Mono Nerd Font", .data = assets.jetbrains_mono_nerd },
    // SF Mono isn't installed by name; this is the system's monospaced face.
    .{ .name = "SF Mono", .system = ".AppleSystemUIFontMonospaced-Regular" },
    .{ .name = "Menlo", .system = "Menlo-Regular" },
};

pub const family_names = blk: {
    var names: [families.len][:0]const u8 = undefined;
    for (families, 0..) |f, i| names[i] = f.name;
    break :blk names;
};

/// The family's index; the default for an unknown name.
pub fn indexOf(name: []const u8) usize {
    for (families, 0..) |f, i| if (std.mem.eql(u8, f.name, name)) return i;
    return 0;
}

/// The editor face's line height at its loaded size.
pub fn lineHeight(text_system: *TextSystem) f32 {
    text_system.useFont(TextSystem.font_id_mono);
    defer text_system.useFont(0);
    return if (text_system.getMetrics()) |m| m.line_height else 0;
}

/// The width of a cell (one column) of the editor face at its loaded size.
pub fn cellWidth(text_system: *TextSystem) f32 {
    text_system.useFont(TextSystem.font_id_mono);
    defer text_system.useFont(0);
    return text_system.measureText("M") catch 8;
}

/// Loads `family` at `size` (clamped) as the editor face, falling back to
/// JetBrains Mono; returns the size used.
pub fn load(text_system: *TextSystem, family: []const u8, size: f32) f32 {
    const clamped = @min(max_size, @max(min_size, size));
    const f = families[indexOf(family)];
    if (f.data) |data| {
        text_system.loadExtraFontData(TextSystem.font_id_mono, data, clamped) catch return theme.mono_font_size;
    } else {
        text_system.loadExtraFont(TextSystem.font_id_mono, f.system, clamped) catch
            text_system.loadExtraFontData(TextSystem.font_id_mono, assets.jetbrains_mono_nerd, clamped) catch return theme.mono_font_size;
    }
    return clamped;
}
