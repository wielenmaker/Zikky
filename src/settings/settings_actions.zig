//! What the settings window's controls do: panes, switches, the excluded
//! folders and the appearance, each saved as it changes.

const std = @import("std");
const gooey = @import("gooey");
const store = @import("../store.zig");
const keys = @import("../keys.zig");
const appearance = @import("../appearance.zig");
const workspace = @import("../tree/workspace.zig");
const settings_panes = @import("settings_panes.zig");
const Settings = @import("settings.zig").Settings;
const AppState = @import("../state.zig").AppState;

pub fn selectPane(s: *AppState, _: *gooey.Window, pane: u8) void {
    s.settings_pane = pane;
    s.settings_query = "";
}

pub fn prevPane(s: *AppState, _: *gooey.Window) void {
    s.settings_pane -|= 1;
}

pub fn nextPane(s: *AppState, _: *gooey.Window) void {
    s.settings_pane = @min(s.settings_pane + 1, settings_panes.panes.len - 1);
}

pub fn flip(s: *AppState, _: *gooey.Window, sw: Settings.Switch) void {
    s.settings.flip(sw);
    save(s, s.main);
    switch (sw) {
        .vim_mode => applyVim(s, s.main),
        .show_hidden => workspace.reload(s, s.main),
        else => {},
    }
    s.main.requestRender();
}

pub fn applyExclude(s: *AppState, _: *gooey.Window) void {
    if (std.mem.eql(u8, s.exclude_edit, s.settings.exclude)) return;
    s.settings.exclude = s.arena.dupe(u8, s.exclude_edit) catch return;
    save(s, s.main);
    workspace.reload(s, s.main);
    s.main.requestRender();
}

pub fn setAppearance(s: *AppState, g: *gooey.Window, mode: Settings.Appearance) void {
    s.settings.appearance = mode;
    appearance.apply(mode);
    save(s, g);
    s.main.requestRender();
    g.requestRender();
}

pub fn save(s: *AppState, g: *gooey.Window) void {
    store.save(g.io, Settings.file, s.settings);
}

/// Keys and clicks go through `keys.capture` (quick open, the terminal,
/// the find bar, vim) before the focused widget.
pub fn applyVim(_: *AppState, g: *gooey.Window) void {
    g.key_capture = keys.capture;
}
