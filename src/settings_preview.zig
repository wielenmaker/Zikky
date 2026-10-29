//! The Appearance pane's sample: a few lines of code in the editor's font,
//! size and syntax colors, on the editor container's background.

const gooey = @import("gooey");
const components = @import("gooey-components");
const theme = @import("theme.zig");
const syntax = @import("syntax.zig");

const ui = gooey.ui;
const Cx = gooey.Cx;
const Color = gooey.Color;
const CodeEditor = components.CodeEditor;

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
        const c = theme.color;
        // The pointer passes by, so the sample can't be edited.
        cx.render(ui.box(.{ .padding = .{ .symmetric = .{ .x = 0, .y = 10 } }, .pointer_events = .none }, .{
            CodeEditor{
                .id = "settings-preview",
                .bind = &sample,
                .width = self.width,
                .height = 136,
                .highlighter = syntax.forName("landmark.zig"),
                .padding = 0,
                .gutter_width = 36,
                .show_status_bar = false,
                .border_width = 0,
                .background = Color.transparent,
                .gutter_background = Color.transparent,
                .gutter_separator_color = Color.transparent,
                .current_line_background = Color.transparent,
                .scrollbar_width = 0,
                .text_color = c.foreground,
                .line_number_color = c.muted.withAlpha(0.6),
                .current_line_number_color = c.muted.withAlpha(0.6),
                .cursor_color = Color.transparent,
                .selection_color = Color.transparent,
            },
        }));
        // The editor takes its text once it exists (created while rendering).
        if (cx.window().widgetState(gooey.widgets.CodeEditorState, "settings-preview")) |ce| {
            if (ce.text_area.getText().len == 0) ce.setText(sample) catch {};
        }
    }
};
