//! Dev tuner: live steppers for the command palette's corner radii, floating
//! beside the card while the palette is open. Delete this file (and its use in
//! `palette_view.zig`) once the radii are settled.

const gooey = @import("gooey");
const theme = @import("theme.zig");
const AppState = @import("state.zig").AppState;
const Stepper = @import("stepper.zig").Stepper;

const ui = gooey.ui;
const Cx = gooey.Cx;

pub var card: f32 = 20;
pub var pill: f32 = 8;
pub var row: f32 = 8;

const Change = enum { card_down, card_up, pill_down, pill_up, row_down, row_up };

fn change(_: *AppState, g: *gooey.Window, c: Change) void {
    switch (c) {
        .card_down => card -= 1,
        .card_up => card += 1,
        .pill_down => pill -= 1,
        .pill_up => pill += 1,
        .row_down => row -= 1,
        .row_up => row += 1,
    }
    card = @max(0, @min(card, 40));
    pill = @max(0, @min(pill, 40));
    row = @max(0, @min(row, 40));
    g.requestRender();
}

const width: f32 = 232;

pub const Tuner = struct {
    /// Where the palette card ends (its half width) and its top.
    palette_half: f32,
    top: f32,

    pub fn render(self: @This(), cx: *Cx) void {
        cx.render(ui.box(.{
            .width = width,
            .background = theme.color.background,
            .corner_radius = theme.radius_lg,
            .border_width = .{ .all = 1 },
            .border_color = theme.color.border.withAlpha(0.8),
            .shadow = .{ .blur_radius = 24, .offset_y = 8, .color = theme.color.card_shadow },
            .padding = .{ .all = 12 },
            .gap = 8,
            .floating = .{ .element_anchor = .left_top, .parent_anchor = .center_top, .offset_x = self.palette_half + 12, .offset_y = self.top, .z_index = 201 },
        }, .{
            ui.text("Corner radius", .{ .size = 12, .weight = .semibold, .color = theme.color.muted }),
            Knob{ .label = "Card", .value = card, .down = cx.commandWith(Change.card_down, change), .up = cx.commandWith(Change.card_up, change) },
            Knob{ .label = "Pill", .value = pill, .down = cx.commandWith(Change.pill_down, change), .up = cx.commandWith(Change.pill_up, change) },
            Knob{ .label = "Row", .value = row, .down = cx.commandWith(Change.row_down, change), .up = cx.commandWith(Change.row_up, change) },
        }));
    }
};

const Knob = struct {
    label: []const u8,
    value: f32,
    down: ui.HandlerRef,
    up: ui.HandlerRef,

    pub fn render(self: @This(), cx: *Cx) void {
        cx.render(ui.box(.{ .fill_width = true, .direction = .row, .alignment = .{ .cross = .center } }, .{
            ui.box(.{ .grow_width = true }, .{ui.text(self.label, .{ .size = 13, .color = theme.color.foreground })}),
            Stepper{ .value = ui.textFmt("{d}", .{self.value}, .{}).content, .on_down = self.down, .on_up = self.up },
        }));
    }
};
