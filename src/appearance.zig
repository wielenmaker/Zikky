//! Light, dark, or following macOS (Settings → Appearance): AppKit's
//! appearance for title bars, menus and panels, and the palette in
//! `theme.color` to match it.

const gooey = @import("gooey");
const theme = @import("theme.zig");
const Mode = @import("settings.zig").Settings.Appearance;

const mac = gooey.platform.macos;

pub fn apply(mode: Mode) void {
    mac.appearance.set(switch (mode) {
        .system => null,
        .light => false,
        .dark => true,
    });
    sync();
}

/// Picks the palette for the app's appearance. Each window calls it as it
/// renders: a light/dark switch (the system's too) re-renders them.
pub fn sync() void {
    theme.color = if (mac.appearance.isDark()) &theme.dark else &theme.light;
}

/// The window's own background (seen while it resizes) in the palette's `color`.
pub fn background(g: *gooey.Window, color: gooey.Color) void {
    const pw = g.platform_window orelse return;
    const c = pw.background_color;
    if (c.r != color.r or c.g != color.g or c.b != color.b or c.a != color.a) pw.setBackgroundColor(color);
}
