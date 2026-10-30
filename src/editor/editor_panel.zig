//! Right side: the tab bar, then a rounded white container holding the code editor.

const std = @import("std");
const gooey = @import("gooey");
const theme = @import("../theme.zig");
const AppState = @import("../state.zig").AppState;
const code_style = @import("../ui/code_style.zig");
const picker = @import("../overlays/picker.zig");
const TabBar = @import("tab_bar.zig").TabBar;
const vim = @import("../vim/vim.zig");
const tabs = @import("tabs.zig");
const syntax = @import("../syntax/syntax.zig");
const FindBar = @import("find_bar.zig").FindBar;
const terminal = @import("../terminal/terminal.zig");
const save = @import("save.zig");
const TermPanel = @import("../terminal/term_view.zig").TermPanel;

const ui = gooey.ui;
const Cx = gooey.Cx;

const padding: f32 = 16;

/// The area right of the sidebar; insets the container on every side the
/// window edge touches (the left too once the sidebar is hidden). The shown
/// tab's terminal (⌘J) sits below it in a container of its own, the inset
/// between them a divider to drag.
pub const EditorPanel = struct {
    width: f32,
    height: f32,

    pub fn render(self: @This(), cx: *Cx) void {
        const s = cx.state(AppState);
        const left: f32 = if (s.sidebar_open) 0 else theme.inset;
        const width = self.width - theme.inset - left;
        // No file open: the container takes the tab bar's row too (not under the hidden sidebar's buttons).
        const fill = s.tabs.count == 0 and s.sidebar_open;
        const top: f32 = if (fill) theme.inset else theme.titlebar_height;
        const below = self.height - top - theme.inset;
        const term = terminal.slot(s).open;
        // The editor keeps at least 120pt; the terminal gets the rest it asked for.
        const term_h: f32 = if (term) std.math.clamp(s.term.height, terminal.min_height, @max(terminal.min_height, below - 120 - theme.inset)) else 0;
        const editor_h = if (term) below - term_h - theme.inset else below;
        if (term) s.term.rect = .{
            .x = (if (s.sidebar_open) theme.sidebar_width else 0) + left,
            .y = top + editor_h + theme.inset,
            .w = width,
            .h = term_h,
        };
        cx.render(ui.box(.{ .width = self.width, .height = self.height }, .{
            ui.when(!fill, .{TabBar{ .width = self.width }}),
            ui.box(.{
                .padding = .{ .each = .{ .top = if (fill) theme.inset else 0, .right = theme.inset, .bottom = theme.inset, .left = left } },
                .gap = theme.inset,
            }, .{
                Container{ .width = width, .height = editor_h },
                ui.when(term, .{TermPanel{ .width = width, .height = term_h }}),
            }),
        }));
    }
};

const Container = struct {
    width: f32,
    height: f32,

    pub fn render(self: @This(), cx: *Cx) void {
        const s = cx.state(AppState);
        const tab = s.tabs.active();
        const id = if (tab) |t| t.id() else tabs.empty_id;
        // A tab's cursor and scroll go in once its editor has been laid out.
        if (tab) |t| if (t.pending) |v| if (tabs.editor(cx.window(), id)) |ce| {
            t.pending = null;
            ce.setText(t.source) catch {};
            ce.text_area.cursor_byte = @min(v.cursor, t.source.len);
            ce.text_area.scroll_offset_y = @min(v.scroll_y, ce.text_area.maxScrollY());
            ce.text_area.scroll_target_y = ce.text_area.scroll_offset_y;
        };
        cx.render(ui.box(.{
            .width = self.width,
            .height = self.height,
            .background = theme.color.background,
            .corner_radius = theme.radius_lg,
            .border_width = .{ .all = 1 },
            .border_color = theme.color.border.withAlpha(0.8),
            .shadow = theme.shadow_xs,
            .padding = .{ .each = .{ .top = theme.editor_top, .right = 0, .bottom = padding, .left = 0 } },
        }, .{ui.when(!s.picker.open, .{
            // Hidden under quick open: text widgets draw above floating cards.
            code_style.editor(.{
                .id = id,
                .bind = if (tab) |t| &t.source else &tabs.scratch,
                .placeholder = if (tab) |t| t.placeholder else "Type something...",
                // Full width: the scrollbar's lane (6 + 5 × 2) is where long lines wrap,
                // 16pt before the right edge, with the bar 5pt from it.
                .width = self.width - 2,
                .soft_wrap = s.settings.soft_wrap,
                .show_line_numbers = s.settings.line_numbers,
                .height = self.height - 2 - theme.editor_top - padding,
                .highlighter = if (tab) |t| syntax.forName(s.tabName(t)) else null,
                // Room for four digits at any zoom, within gooey's gutter cap.
                .gutter_width = @min(gooey.widgets.code_editor_state.MAX_GUTTER_WIDTH, 48 * s.settings.font_size / theme.mono_font_size),
                .language_mode = "Zig",
                .current_line_background = theme.color.current_line,
                .current_line_number_color = theme.color.foreground,
                .cursor_color = theme.color.primary,
            }),
            ui.when(s.find.open, .{FindBar{}}),
        }), ui.when(save.unsaved(s, cx.window()), .{save.Badge{}})}));
        if (!s.picker.open) if (tabs.editor(cx.window(), id)) |ce| prepare(s, cx.window(), ce, id);
    }
};

/// Once the editor exists: vim's block cursor, a new one's text (its view
/// follows next frame), the focus it inherits.
fn prepare(s: *AppState, g: *gooey.Window, ce: *gooey.widgets.CodeEditorState, id: []const u8) void {
    ce.text_area.cursor_block = s.settings.vim_mode and vim.vim.mode == .normal;
    if (s.tabs.active()) |t| if (t.pending != null) {
        ce.setText(t.source) catch {};
        g.requestRender();
    };
    if (s.tabs.focus) {
        s.tabs.focus = false;
        g.focusWidget(id);
    }
}
