//! A shortcut's keys in Settings › Keyboard: click, then press the new keys
//! (Escape cancels). Changed keys get a button back to the default.

const gooey = @import("gooey");
const components = @import("gooey-components");
const theme = @import("../theme.zig");
const AppState = @import("../state.zig").AppState;
const shortcuts = @import("../shortcuts/shortcuts.zig");
const recorder = @import("../shortcuts/recorder.zig");
const combo = @import("../shortcuts/combo.zig");
const clickable = @import("../ui/clickable.zig");
const IconButton = @import("../ui/icon_button.zig").IconButton;
const KeysLabel = @import("../ui/keys_label.zig").KeysLabel;

const ui = gooey.ui;
const Cx = gooey.Cx;
const Lucide = components.Lucide;

pub const ShortcutField = struct {
    id: shortcuts.Id,

    pub fn render(self: @This(), cx: *Cx) void {
        const s = cx.state(AppState);
        const c = theme.color.settings;
        const recording = s.recording == self.id;
        const keys = combo.first(shortcuts.keys(&s.settings, self.id));
        cx.render(ui.box(.{ .direction = .row, .alignment = .{ .cross = .center }, .gap = 6 }, .{
            ui.when(!shortcuts.isDefault(&s.settings, self.id), .{
                IconButton{ .icon = Lucide.rotate_ccw, .icon_size = 13, .on_click = cx.commandWith(self.id, shortcuts.reset) },
            }),
            clickable.box(.{ .fill = c.input_bg, .on_click = cx.commandWith(self.id, recorder.start) }, .{
                .min_width = 64,
                .height = 24,
                .corner_radius = 5,
                .border_width = .{ .all = 1 },
                .border_color = if (recording) c.accent else c.input_border,
                .padding = .{ .symmetric = .{ .x = 8, .y = 0 } },
                .alignment = .{ .main = .center, .cross = .center },
            }, .{
                ui.when(recording, .{ui.text("Press keys…", .{ .size = theme.settings.text_size, .color = c.accent })}),
                ui.when(!recording and keys.len == 0, .{ui.text("None", .{ .size = theme.settings.text_size, .color = theme.color.muted })}),
                ui.when(!recording and keys.len > 0, .{KeysLabel{ .combo = keys, .size = theme.settings.text_size, .color = c.label }}),
            }),
        }));
    }
};
