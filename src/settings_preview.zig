//! The Appearance pane's sample: a few lines of code in the editor's font,
//! size and syntax colors, on the editor container's background.

const gooey = @import("gooey");
const syntax = @import("syntax.zig");
const code_style = @import("code_style.zig");

const ui = gooey.ui;
const Cx = gooey.Cx;
const Color = gooey.Color;

var sample: []const u8 =
    \\const std = @import("std");
    \\
    \\/// A place worth a visit, with how much people like it.
    \\pub const Landmark = struct {
    \\    name: []const u8 = "Golden Gate",
    \\    rating: u8 = 5,
    \\};
;

pub const SettingsPreview = struct {
    width: f32,

    pub fn render(self: @This(), cx: *Cx) void {
        // The pointer passes by, so the sample can't be edited.
        cx.render(ui.box(.{ .padding = .{ .symmetric = .{ .x = 0, .y = 10 } }, .pointer_events = .none }, .{
            code_style.editor(.{
                .id = "settings-preview",
                .bind = &sample,
                .width = self.width,
                .height = 136,
                .highlighter = syntax.forName("landmark.zig"),
                .gutter_width = 36,
                .scrollbar_width = 0,
                .selection_color = Color.transparent,
            }),
        }));
        // The editor takes its text once it exists (created while rendering).
        if (cx.window().widgetState(gooey.widgets.CodeEditorState, "settings-preview")) |ce| {
            if (ce.text_area.getText().len == 0) ce.setText(sample) catch {};
        }
    }
};
