const std = @import("std");
const gooey = @import("gooey");
const theme = @import("theme.zig");
const AppState = @import("state.zig").AppState;
const workspace = @import("tree/workspace.zig");
const tab_actions = @import("editor/tab_actions.zig");
const settings_actions = @import("settings/settings_actions.zig");
const picker = @import("overlays/picker.zig");
const font_actions = @import("editor/font_actions.zig");
const sidebar = @import("tree/sidebar.zig");
const EditorPanel = @import("editor/editor_panel.zig").EditorPanel;
const editor_font = @import("editor/editor_font.zig");
const app_menu = @import("app_menu.zig");
const shortcuts = @import("shortcuts/shortcuts.zig");
const store = @import("store.zig");
const Settings = @import("settings/settings.zig").Settings;
const session = @import("session.zig");
const settings_window = @import("settings/settings_window.zig");
const PickerView = @import("overlays/picker_view.zig").PickerView;
const appearance = @import("appearance.zig");
const find = @import("editor/find.zig");
const palette = @import("overlays/palette.zig");
const PaletteView = @import("overlays/palette_view.zig").PaletteView;
const terminal = @import("terminal/terminal.zig");
const save = @import("editor/save.zig");

const ui = gooey.ui;
const Cx = gooey.Cx;

var state = AppState{};
var app: gooey.runtime.MultiWindowApp = undefined;
/// The last session, when it is to be restored.
var last: ?session.Session = null;

fn onInit(cx: *Cx, s: *AppState) void {
    // UI text uses the primary face (SF Pro); the editor uses JetBrains Mono.
    const ts = cx.window().resources.text_system;
    s.main = cx.window();
    font_actions.apply(s, cx.window());
    ts.loadExtraFont(gooey.text.TextSystem.font_id_bold, ".AppleSystemUIFontDemi", theme.ui_font_size) catch {};
    terminal.init(cx.window());
    shortcuts.apply(s, cx.window());
    settings_actions.applyVim(s, cx.window());
    cx.window().platform_window.?.autosaveFrame("Zikky");
    workspace.load(s, cx.window().io);
    if (s.noFolder()) workspace.untitled(s, cx.window());
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
    const sidebar_width: f32 = if (cx.state(AppState).sidebar_open) theme.sidebar_width else 0;
    cx.render(ui.box(.{
        .width = size.width,
        .height = size.height,
        .background = theme.color.sidebar_bg,
        .direction = .row,
    }, .{
        ui.onActionHandler(editor_font.ZoomIn, cx.command(font_actions.zoomIn)),
        ui.onActionHandler(editor_font.ZoomOut, cx.command(font_actions.zoomOut)),
        ui.onActionHandler(editor_font.ZoomReset, cx.command(font_actions.zoomReset)),
        ui.onActionHandler(sidebar.ToggleSidebar, cx.command(AppState.toggleSidebar)),
        ui.onActionHandler(app_menu.CloseFile, cx.command(tab_actions.closeShown)),
        ui.onActionHandler(app_menu.OpenFolder, cx.command(workspace.openFolder)),
        ui.onActionHandler(app_menu.OpenSettings, cx.command(settings_window.open)),
        ui.onActionHandler(app_menu.QuickOpen, cx.command(picker.open)),
        ui.onActionHandler(app_menu.Save, cx.command(save.run)),
        ui.onActionHandler(find.Open, cx.command(find.open)),
        ui.onActionHandler(palette.Open, cx.command(palette.toggle)),
        ui.onActionHandler(find.Next, cx.command(find.next)),
        ui.onActionHandler(find.Prev, cx.command(find.prev)),
        ui.onActionHandler(terminal.Toggle, cx.command(terminal.toggle)),
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
    _ = @import("tree/fs_tree.zig");
    _ = @import("ui/file_kind.zig");
    _ = @import("syntax/syntax.zig");
    _ = @import("syntax/syntax_markup.zig");
    _ = @import("vim/vim_motion.zig");
    _ = @import("settings/settings.zig");
    _ = @import("overlays/fuzzy.zig");
    _ = @import("editor/find.zig");
    _ = @import("overlays/palette.zig");
    _ = @import("shortcuts/combo.zig");
}

/// `zikky [folder]` opens `folder`; without one, the last session's folder
/// (if restoring is on), else the current directory, or from the app bundle
/// none: just the editor, with an Untitled tab.
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
    if (init.environ_map.get("HOME")) |home| store.dir = try std.fs.path.join(state.arena, &.{ home, "Library/Application Support/Zikky" });
    state.settings = store.load(Settings, state.arena, init.io, Settings.file);
    const ses = store.load(session.Session, state.arena, init.io, session.Session.file_name);
    if (args.len == 1 and state.settings.restore_session and ses.folder.len > 0 and exists(init.io, ses.folder)) {
        state.root = ses.folder;
        last = ses;
    }
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
