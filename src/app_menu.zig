//! The menu bar. Items with a `code` replay their shortcut, so each one runs
//! the same keymap binding as its keys; the rest are standard AppKit actions.

const gooey = @import("gooey");

const menu = gooey.platform.macos.menu;
const Item = menu.Item;

pub const CloseFile = struct {};
pub const OpenFolder = struct {};
pub const OpenSettings = struct {};
pub const QuickOpen = struct {};

const shift_cmd = gooey.input.Modifiers{ .cmd = true, .shift = true };
const sep = Item{};

const menus = [_]menu.Menu{
    .{ .title = "Zikky", .items = &.{
        .{ .title = "About Zikky", .action = "orderFrontStandardAboutPanel:" },
        sep,
        .{ .title = "Settings…", .key = ",", .code = .comma },
        sep,
        .{ .title = "Hide Zikky", .key = "h", .action = "hide:" },
        .{ .title = "Hide Others", .key = "h", .mods = .{ .cmd = true, .alt = true }, .action = "hideOtherApplications:" },
        .{ .title = "Show All", .action = "unhideAllApplications:" },
        sep,
        .{ .title = "Quit Zikky", .key = "q", .action = "terminate:" },
    } },
    .{ .title = "File", .items = &.{
        .{ .title = "Quick Open…", .key = "o", .code = .o },
        .{ .title = "Open Folder…", .key = "o", .mods = shift_cmd, .code = .o },
        sep,
        .{ .title = "Close Tab", .key = "w", .code = .w },
    } },
    .{ .title = "Edit", .items = &.{
        .{ .title = "Undo", .key = "z", .code = .z },
        .{ .title = "Redo", .key = "z", .mods = shift_cmd, .code = .z },
        sep,
        .{ .title = "Cut", .key = "x", .code = .x },
        .{ .title = "Copy", .key = "c", .code = .c },
        .{ .title = "Paste", .key = "v", .code = .v },
        .{ .title = "Select All", .key = "a", .code = .a },
        sep,
        .{ .title = "Find…", .key = "f", .code = .f },
        .{ .title = "Find Next", .key = "g", .code = .g },
        .{ .title = "Find Previous", .key = "g", .mods = shift_cmd, .code = .g },
    } },
    .{ .title = "View", .items = &.{
        .{ .title = "Toggle Sidebar", .key = "\\", .code = .backslash },
        .{ .title = "Toggle Terminal", .key = "j", .code = .j },
        sep,
        .{ .title = "Zoom In", .key = "=", .code = .equal },
        .{ .title = "Zoom Out", .key = "-", .code = .minus },
        .{ .title = "Actual Size", .key = "0", .code = .@"0" },
    } },
    .{ .title = "Window", .items = &.{
        .{ .title = "Minimize", .key = "m", .action = "performMiniaturize:" },
        .{ .title = "Zoom", .action = "performZoom:" },
    } },
};

pub fn install(g: *gooey.Window) void {
    menu.setMainMenu(&menus);
    g.keymap().bind(CloseFile, "cmd-w", null);
    g.keymap().bind(OpenFolder, "cmd-shift-o", null);
    g.keymap().bind(OpenSettings, "cmd-,", null);
    g.keymap().bind(QuickOpen, "cmd-o", null);
    g.keymap().bind(QuickOpen, "cmd-p", null);
}
