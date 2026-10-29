const std = @import("std");
const gooey = @import("gooey");
const theme = @import("theme.zig");
const AppState = @import("state.zig").AppState;
const sidebar = @import("sidebar.zig");
const EditorPanel = @import("editor_panel.zig").EditorPanel;
const editor_font = @import("editor_font.zig");
const app_menu = @import("app_menu.zig");
const store = @import("store.zig");
const Settings = @import("settings.zig").Settings;
const session = @import("session.zig");
const settings_window = @import("settings_window.zig");
const PickerView = @import("picker_view.zig").PickerView;
const appearance = @import("appearance.zig");
const find = @import("find.zig");
const palette = @import("palette.zig");
const PaletteView = @import("palette_view.zig").PaletteView;
const terminal = @import("terminal.zig");
const welcome = @import("welcome.zig");
const save = @import("save.zig");
const assets = @import("assets");

const ui = gooey.ui;
const Cx = gooey.Cx;

var state = AppState{};
var app: gooey.runtime.MultiWindowApp = undefined;
/// The last session, when it is to be restored.
var last: ?session.Session = null;

fn onInit(cx: *Cx, s: *AppState) void {
    // UI text uses the primary face (SF Pro); the editor uses Paper Mono.
    const ts = cx.window().resources.text_system;
    s.main = cx.window();
    s.applyFont(cx.window());
    ts.loadExtraFont(gooey.text.TextSystem.font_id_bold, ".AppleSystemUIFontDemi", theme.ui_font_size) catch {};
    editor_font.bindKeys(cx.window());
    sidebar.bindKeys(cx.window());
    find.bindKeys(cx.window());
    palette.bindKeys(cx.window());
    terminal.bindKeys(cx.window());
    app_menu.install(cx.window());
    s.applyVim(cx.window());
    cx.window().platform_window.?.autosaveFrame("Zikky");
    s.load(cx.window().io);
    if (s.tree.node_count > 0) s.remember(s.paths[0]);
    if (last) |ses| session.restore(s, cx.window(), ses);
}

/// Closing the window or quitting the app saves the session. Closing also
/// closes settings, so the app quits, like single-window Mac apps.
fn onClose(cx: *Cx) bool {
    session.save(cx.state(AppState), cx.window());
    settings_window.hide(cx.state(AppState), cx.window());
    return true;
}

fn render(cx: *Cx) void {
    appearance.sync();
    appearance.background(cx.window(), theme.color.sidebar_bg);
    const size = cx.windowSize();
    if (cx.state(AppState).welcome()) return cx.render(ui.box(.{
        .width = size.width,
        .height = size.height,
        .background = theme.color.sidebar_bg,
    }, .{
        ui.onActionHandler(app_menu.OpenFolder, cx.command(AppState.openFolder)),
        ui.onActionHandler(app_menu.OpenSettings, cx.command(settings_window.open)),
        welcome.Welcome{ .width = size.width, .height = size.height },
    }));
    const sidebar_width: f32 = if (cx.state(AppState).sidebar_open) theme.sidebar_width else 0;
    cx.render(ui.box(.{
        .width = size.width,
        .height = size.height,
        .background = theme.color.sidebar_bg,
        .direction = .row,
    }, .{
        ui.onActionHandler(editor_font.ZoomIn, cx.command(AppState.zoomIn)),
        ui.onActionHandler(editor_font.ZoomOut, cx.command(AppState.zoomOut)),
        ui.onActionHandler(editor_font.ZoomReset, cx.command(AppState.zoomReset)),
        ui.onActionHandler(sidebar.ToggleSidebar, cx.command(AppState.toggleSidebar)),
        ui.onActionHandler(app_menu.CloseFile, cx.command(AppState.close)),
        ui.onActionHandler(app_menu.OpenFolder, cx.command(AppState.openFolder)),
        ui.onActionHandler(app_menu.OpenSettings, cx.command(settings_window.open)),
        ui.onActionHandler(app_menu.QuickOpen, cx.command(AppState.openPicker)),
        ui.onActionHandler(app_menu.Save, cx.command(save.run)),
        ui.onActionHandler(find.Open, cx.command(find.open)),
        ui.onActionHandler(palette.Open, cx.command(palette.toggle)),
        ui.onActionHandler(find.Next, cx.command(find.next)),
        ui.onActionHandler(find.Prev, cx.command(find.prev)),
        ui.onActionHandler(terminal.Toggle, cx.command(AppState.toggleTerminal)),
        ui.when(sidebar_width > 0, .{sidebar.Sidebar{}}),
        EditorPanel{ .width = size.width - sidebar_width, .height = size.height },
        ui.when(cx.state(AppState).picker.open, .{PickerView{ .width = size.width, .height = size.height }}),
        ui.when(cx.state(AppState).palette.open, .{PaletteView{ .window_width = size.width, .window_height = size.height }}),
    }));
}

fn mainWindow() gooey.runtime.AppWindowOptions {
    return .{
        .title = "",
        .width = 1280,
        .height = 820,
        .min_size = gooey.core.Size(f64){ .width = 720, .height = 480 },
        .background_color = theme.color.sidebar_bg,
        .titlebar_transparent = true,
        .full_size_content = true,
        .traffic_light_position = gooey.core.Point(f64){ .x = theme.traffic_lights.x, .y = theme.traffic_lights.y },
        .on_close = onClose,
    };
}

test {
    _ = @import("fs_tree.zig");
    _ = @import("file_kind.zig");
    _ = @import("syntax.zig");
    _ = @import("syntax_markup.zig");
    _ = @import("vim_motion.zig");
    _ = @import("settings.zig");
    _ = @import("fuzzy.zig");
    _ = @import("find.zig");
    _ = @import("palette.zig");
}

/// `zikky [folder]` opens `folder`; without one, the last session's folder
/// (if restoring is on), else the current directory, or from the app bundle
/// the welcome screen.
pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    state.arena = init.arena.allocator();
    // Finder starts apps in /: from the app bundle, start in the home folder
    // (the terminal's), with no folder open.
    const exe = try std.process.executablePathAlloc(init.io, state.arena);
    const bundled = std.mem.indexOf(u8, exe, ".app/Contents/MacOS/") != null;
    if (init.environ_map.get("HOME")) |home| if (bundled) std.process.setCurrentPath(init.io, home) catch {};
    if (bundled) state.root = "";
    if (args.len > 1) state.root = args[1];
    welcome.home = init.environ_map.get("HOME") orelse "";
    if (init.environ_map.get("HOME")) |home| store.dir = try std.fs.path.join(state.arena, &.{ home, "Library/Application Support/Zikky" });
    state.settings = store.load(Settings, state.arena, init.io, Settings.file);
    const ses = store.load(session.Session, state.arena, init.io, session.Session.file_name);
    // Oldest first, so the newest ends up in front.
    var i = ses.recent.len;
    while (i > 0) : (i -= 1) if (exists(init.io, ses.recent[i - 1])) state.remember(ses.recent[i - 1]);
    if (args.len == 1 and state.settings.restore_session and ses.folder.len > 0 and exists(init.io, ses.folder)) {
        state.root = ses.folder;
        last = ses;
    }
    gooey.image.loader.embedded = &.{.{ .name = welcome.logo, .data = assets.logo }};
    try app.initInPlace(init.gpa, .{ .font_size = theme.ui_font_size }, init.io);
    appearance.apply(state.settings.appearance);
    app.quit_policy = .last_window_closed;
    settings_window.app = &app;
    const handle = try app.openWindow(AppState, &state, render, mainWindow());
    handle.updateWithCx(app.getPlatform(), onInit);
    app.run();
}

fn exists(io: std.Io, path: []const u8) bool {
    std.Io.Dir.access(.cwd(), io, path, .{}) catch return false;
    return true;
}
