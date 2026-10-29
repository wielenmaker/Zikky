//! Where keys and clicks go first (`Window.key_capture`), before the focused
//! widget: quick open while it shows, then the terminal (clicks, the wheel,
//! and keys while focused), the find bar, and vim in the editor.

const gooey = @import("gooey");
const AppState = @import("state.zig").AppState;
const picker = @import("picker.zig");
const find = @import("find.zig");
const terminal = @import("terminal.zig");
const vim = @import("vim.zig");

pub fn capture(g: *gooey.Window, event: gooey.input.InputEvent) bool {
    const s = g.getRootState(AppState) orelse return false;
    if (s.picker.open) return picker.capture(g, event);
    if (terminal.capture(s, g, event)) return true;
    if (s.find.open and find.capture(g, event)) return true;
    return s.settings.vim_mode and vim.capture(g, event);
}
