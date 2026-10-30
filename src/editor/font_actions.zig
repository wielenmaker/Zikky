//! The editor font's family and size: loading it, zoom (⌘+ / ⌘− / ⌘0) and
//! the settings' font menu. The terminal's cell follows it.

const gooey = @import("gooey");
const theme = @import("../theme.zig");
const editor_font = @import("editor_font.zig");
const settings_actions = @import("../settings/settings_actions.zig");
const AppState = @import("../state.zig").AppState;

pub fn zoomIn(s: *AppState, g: *gooey.Window) void {
    setSize(s, g, s.settings.font_size + 1);
}

pub fn zoomOut(s: *AppState, g: *gooey.Window) void {
    setSize(s, g, s.settings.font_size - 1);
}

pub fn zoomReset(s: *AppState, g: *gooey.Window) void {
    setSize(s, g, theme.mono_font_size);
}

fn setSize(s: *AppState, g: *gooey.Window, size: f32) void {
    s.settings.font_size = editor_font.load(g.resources.text_system, s.settings.font, size);
    measureCell(s, g);
    settings_actions.save(s, g);
    s.main.requestRender();
}

/// Loads the editor font, measuring its line height at the default size first.
pub fn apply(s: *AppState, g: *gooey.Window) void {
    const ts = g.resources.text_system;
    _ = editor_font.load(ts, s.settings.font, theme.mono_font_size);
    s.line_height = editor_font.lineHeight(ts);
    s.settings.font_size = editor_font.load(ts, s.settings.font, s.settings.font_size);
    measureCell(s, g);
}

fn measureCell(s: *AppState, g: *gooey.Window) void {
    const ts = g.resources.text_system;
    s.cell_h = @ceil(editor_font.lineHeight(ts));
    s.cell_w = editor_font.cellWidth(ts);
}

/// The font control: a menu of the families. Deferred: it runs a nested event loop.
pub fn pick(_: *AppState, g: *gooey.Window) void {
    g.deferCommand(showMenu);
}

fn showMenu(s: *AppState, g: *gooey.Window) void {
    const mac = gooey.platform.macos;
    const i = mac.menu.popUpSelect(&editor_font.family_names, editor_font.indexOf(s.settings.font)) orelse return;
    s.settings.font = editor_font.families[i].name;
    apply(s, g);
    settings_actions.save(s, g);
    s.main.requestRender();
    g.requestRender();
}
