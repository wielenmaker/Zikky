//! The menu bar. Items with a `code` replay their shortcut, so each one runs
//! the same keymap binding as its keys; the rest are standard AppKit actions.
//! Rebuilt when a shortcut changes (`shortcuts.apply`).

const gooey = @import("gooey");
const Settings = @import("settings/settings.zig").Settings;
const shortcuts = @import("shortcuts/shortcuts.zig");
const combo = @import("shortcuts/combo.zig");

const menu = gooey.platform.macos.menu;
const Item = menu.Item;

pub const CloseFile = struct {};
pub const OpenFile = struct {};
pub const OpenFolder = struct {};
pub const OpenSettings = struct {};
pub const QuickOpen = struct {};
pub const Save = struct {};

const shift_cmd = gooey.input.Modifiers{ .cmd = true, .shift = true };
const sep = Item{};

const window = [_]Item{
    .{ .title = "Minimize", .key = "m", .action = "performMiniaturize:" },
    .{ .title = "Zoom", .action = "performZoom:" },
};

pub fn install(set: *const Settings) void {
    const app = [_]Item{
        .{ .title = "About Zikky", .action = "orderFrontStandardAboutPanel:" },
        sep,
        bound(set, "Settings…", .settings),
        sep,
        .{ .title = "Hide Zikky", .key = "h", .action = "hide:" },
        .{ .title = "Hide Others", .key = "h", .mods = .{ .cmd = true, .alt = true }, .action = "hideOtherApplications:" },
        .{ .title = "Show All", .action = "unhideAllApplications:" },
        sep,
        .{ .title = "Quit Zikky", .key = "q", .action = "terminate:" },
    };
    const file = [_]Item{
        bound(set, "Quick Open…", .quick_open),
        bound(set, "Open File…", .open_file),
        bound(set, "Open Folder…", .open_folder),
        bound(set, "Save", .save),
        sep,
        bound(set, "Close Tab", .close_tab),
    };
    const edit = [_]Item{
        .{ .title = "Undo", .key = "z", .code = .z },
        .{ .title = "Redo", .key = "z", .mods = shift_cmd, .code = .z },
        sep,
        .{ .title = "Cut", .key = "x", .code = .x },
        .{ .title = "Copy", .key = "c", .code = .c },
        .{ .title = "Paste", .key = "v", .code = .v },
        .{ .title = "Select All", .key = "a", .code = .a },
        sep,
        bound(set, "Find…", .find),
        bound(set, "Find Next", .find_next),
        bound(set, "Find Previous", .find_prev),
    };
    const view = [_]Item{
        bound(set, "Toggle Sidebar", .sidebar),
        bound(set, "Toggle Terminal", .terminal),
        bound(set, "Command Palette…", .palette),
        sep,
        bound(set, "Zoom In", .zoom_in),
        bound(set, "Zoom Out", .zoom_out),
        bound(set, "Actual Size", .zoom_reset),
    };
    menu.setMainMenu(&.{
        .{ .title = "Zikky", .items = &app },
        .{ .title = "File", .items = &file },
        .{ .title = "Edit", .items = &edit },
        .{ .title = "View", .items = &view },
        .{ .title = "Window", .items = &window },
    });
}

/// An item that replays the shortcut's first keys; disabled while it has none.
fn bound(set: *const Settings, title: [:0]const u8, id: shortcuts.Id) Item {
    const c = combo.first(shortcuts.keys(set, id));
    const ks = gooey.input.Keystroke.parse(c) orelse return .{ .title = title };
    return .{ .title = title, .key = combo.keyChar(c), .mods = ks.modifiers, .code = ks.key };
}
