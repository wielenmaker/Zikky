//! The settings window (⌘,), its own window like Rex's, over the same
//! AppState; its changes reach the main window through `AppState.main`.
//! Closing it frees its surfaces.

const gooey = @import("gooey");
const theme = @import("../theme.zig");
const AppState = @import("../state.zig").AppState;
const app_menu = @import("../app_menu.zig");
const SettingsPage = @import("settings_page.zig").SettingsPage;
const appearance = @import("../appearance.zig");
const recorder = @import("../shortcuts/recorder.zig");

const ui = gooey.ui;
const Cx = gooey.Cx;
const Handle = gooey.runtime.WindowHandle(AppState);

pub var app: *gooey.runtime.MultiWindowApp = undefined;
var handle = Handle.invalid();

/// Opens the window, or brings it to the front. Deferred: it runs from a
/// key or menu event, which holds the input lock.
pub fn open(_: *AppState, g: *gooey.Window) void {
    g.deferCommand(show);
}

pub fn close(_: *AppState, g: *gooey.Window) void {
    g.deferCommand(hide);
}

fn show(s: *AppState, _: *gooey.Window) void {
    const plat = app.getPlatform();
    if (handle.isValid(plat)) return handle.focus(plat);
    s.exclude_edit = s.settings.exclude;
    s.recording = null;
    handle = app.openWindow(AppState, s, render, .{
        .title = "",
        .width = 760,
        .height = 560,
        .min_size = .{ .width = 600, .height = 400 },
        .background_color = theme.color.settings.content_bg,
        .titlebar_transparent = true,
        .full_size_content = true,
    }) catch return;
}

/// Not deferred: also called as the main window closes.
pub fn hide(_: *AppState, _: *gooey.Window) void {
    const plat = app.getPlatform();
    if (handle.isValid(plat)) handle.close(plat);
}

fn render(cx: *Cx) void {
    appearance.sync();
    appearance.background(cx.window(), theme.color.settings.content_bg);
    cx.window().key_capture = recorder.capture;
    const size = cx.windowSize();
    cx.render(ui.box(.{ .width = size.width, .height = size.height }, .{
        ui.onActionHandler(app_menu.CloseFile, cx.command(close)),
        ui.onActionHandler(app_menu.OpenSettings, cx.command(open)),
        SettingsPage{ .width = size.width, .height = size.height },
    }));
}
