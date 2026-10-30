//! A shortcut's keys as shown, "⇧⌘" then "O": static strings, so a list of
//! them needs no format buffers.

const gooey = @import("gooey");
const combo = @import("../shortcuts/combo.zig");

const ui = gooey.ui;
const Cx = gooey.Cx;

pub const KeysLabel = struct {
    /// One combo, e.g. "shift-cmd-o".
    combo: []const u8,
    size: u16,
    color: gooey.Color,

    pub fn render(self: @This(), cx: *Cx) void {
        const style = ui.TextStyle{ .size = self.size, .color = self.color };
        cx.render(ui.box(.{ .direction = .row }, .{
            ui.text(combo.modsLabel(self.combo), style),
            ui.text(combo.keyLabel(self.combo), style),
        }));
    }
};
