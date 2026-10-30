//! The code editors' shared look (the editor, quick open's preview, the
//! settings sample): no border, gutter or status bar chrome, theme colors.

const gooey = @import("gooey");
const components = @import("gooey-components");
const theme = @import("../theme.zig");
const props = @import("props.zig");

const Color = gooey.Color;
const CodeEditor = components.CodeEditor;

/// `over` sets at least `.id`, `.width` and `.height`; a read-only look
/// unless it sets the cursor and current line.
pub fn editor(over: anytype) CodeEditor {
    const c = theme.color;
    const quiet = c.muted.withAlpha(0.6);
    return props.with(CodeEditor{
        .id = "",
        .padding = 0,
        .gutter_width = 48,
        .show_status_bar = false,
        .border_width = 0,
        .background = Color.transparent,
        .gutter_background = Color.transparent,
        .gutter_separator_color = Color.transparent,
        .current_line_background = Color.transparent,
        .scrollbar_width = 6,
        .scrollbar_padding = 5,
        .scrollbar_track_color = Color.transparent,
        .scrollbar_thumb_color = c.scrollbar,
        .text_color = c.foreground,
        .placeholder_color = c.muted,
        .line_number_color = quiet,
        .current_line_number_color = quiet,
        .cursor_color = Color.transparent,
        .selection_color = c.primary.withAlpha(0.18),
    }, over);
}
