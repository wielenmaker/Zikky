//! Recording a shortcut's new keys in the settings window: the next key with
//! ⌘, ⌃ or ⌥ becomes its keys; Escape stops. Menu key equivalents come
//! through too, as the menu replays them to the key window.

const gooey = @import("gooey");
const AppState = @import("../state.zig").AppState;
const shortcuts = @import("shortcuts.zig");
const combo = @import("combo.zig");

pub fn start(s: *AppState, _: *gooey.Window, id: shortcuts.Id) void {
    s.recording = id;
}

/// The settings window's `Window.key_capture`: keys while a shortcut records.
pub fn capture(g: *gooey.Window, event: gooey.input.InputEvent) bool {
    const s = g.getRootState(AppState) orelse return false;
    const id = s.recording orelse return false;
    const k = switch (event) {
        .key_down => |k| k,
        else => return false,
    };
    if (k.key == .escape) {
        s.recording = null;
        return true;
    }
    var buf: [32]u8 = undefined;
    const c = combo.fromEvent(&buf, k.key, k.modifiers) orelse return true;
    s.recording = null;
    shortcuts.assign(s, id, s.arena.dupe(u8, c) catch return true);
    return true;
}
