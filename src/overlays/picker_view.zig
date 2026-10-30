//! Quick open on screen: the window dimmed, then two separate rounded cards
//! like the editor's container: the query and file list, and the preview.

const std = @import("std");
const gooey = @import("gooey");
const components = @import("gooey-components");
const theme = @import("../theme.zig");
const AppState = @import("../state.zig").AppState;
const picker = @import("picker.zig");
const fuzzy = @import("fuzzy.zig");
const file_kind = @import("../ui/file_kind.zig");
const FileIcon = @import("../ui/file_icon.zig").FileIcon;
const clickable = @import("../ui/clickable.zig");
const card = @import("../ui/card.zig");
const field = @import("../ui/field.zig");
const code_style = @import("../ui/code_style.zig");

const ui = gooey.ui;
const Cx = gooey.Cx;
const Color = gooey.Color;
const Svg = components.Svg;
const Lucide = components.Lucide;

const margin: f32 = 32;
const gap: f32 = 10;
const header_height: f32 = 40;

pub const PickerView = struct {
    width: f32,
    height: f32,

    pub fn render(self: @This(), cx: *Cx) void {
        picker.refresh(cx.state(AppState), cx.window());
        const card_w = (self.width - 2 * margin - gap) / 2;
        const card_h = self.height - 2 * margin;
        cx.render(ui.box(.{
            .width = self.width,
            .height = self.height,
            .background = theme.color.dim,
            .floating = .{ .z_index = 200 },
            .on_click_handler = cx.command(close),
        }, .{}));
        cx.render(ui.box(.{
            .direction = .row,
            .gap = gap,
            .floating = .{ .z_index = 201, .offset_x = margin, .offset_y = margin },
        }, .{
            Card{ .width = card_w, .height = card_h, .content = .list },
            Card{ .width = card_w, .height = card_h, .content = .preview },
        }));
    }

    fn close(s: *AppState, g: *gooey.Window) void {
        picker.close(s, g);
    }
};

const Card = struct {
    width: f32,
    height: f32,
    content: enum { list, preview },

    pub fn render(self: @This(), cx: *Cx) void {
        cx.render(card.box(.{ .width = self.width, .height = self.height }, .{
            ui.when(self.content == .list, .{ Query{}, card.Divider{}, List{ .height = self.height - header_height - 2 } }),
            ui.when(self.content == .preview, .{ Title{}, card.Divider{}, Preview{ .width = self.width - 2, .height = self.height - header_height - 2 } }),
        }));
    }
};

/// ›, the query field and the n/total count.
const Query = struct {
    pub fn render(_: @This(), cx: *Cx) void {
        const p = &cx.state(AppState).picker;
        cx.render(ui.box(.{
            .fill_width = true,
            .height = header_height,
            .direction = .row,
            .alignment = .{ .cross = .center },
            .padding = .{ .symmetric = .{ .x = 12, .y = 0 } },
            .gap = 6,
        }, .{
            Svg{ .path = Lucide.chevron_right, .size = 16, .no_fill = true, .stroke_color = theme.color.primary, .stroke_width = 2 },
            // Fills only what the count leaves, so the count stays inside the card.
            ui.box(.{ .grow_width = true }, .{field.bare("picker-query", .{ .bind = &p.query, .placeholder = "Search files" })}),
            ui.textFmt("{d}/{d}", .{ p.count, p.total }, .{ .size = 13, .color = theme.color.muted }),
        }));
        if (p.focus_query) {
            p.focus_query = false;
            cx.window().focusWidget("picker-query");
        }
    }
};

const List = struct {
    height: f32,

    pub fn render(self: @This(), cx: *Cx) void {
        const p = &cx.state(AppState).picker;
        cx.lists.uniform("picker-list", &p.list, .{
            .fill_width = true,
            .height = self.height,
            .padding = .{ .all = 6 },
            .thumb_color = theme.color.scrollbar,
            .scrollbar_size = 6,
        }, Row.render);
    }
};

const Row = struct {
    fn render(index: u32, cx: *Cx) void {
        const s = cx.state(AppState);
        const path = s.picker.path(index);
        const kind = file_kind.of(std.fs.path.basename(path));
        cx.render(clickable.box(.{
            .fill = if (index == s.picker.selected) theme.color.sidebar_accent else Color.transparent,
            .on_click = cx.commandWith(index, picker.pick),
        }, .{
            .fill_width = true,
            .height = picker.row_height,
            .direction = .row,
            .alignment = .{ .cross = .center },
            .padding = .{ .symmetric = .{ .x = 8, .y = 0 } },
            .gap = 8,
            .corner_radius = theme.radius,
        }, .{
            FileIcon{ .kind = kind, .size = 14 },
            Path{ .path = path, .query = s.picker.query },
        }));
    }
};

/// The path with its folders dimmed and the matched letters in the accent color.
const Path = struct {
    path: []const u8,
    query: []const u8,

    pub fn render(self: @This(), cx: *Cx) void {
        var buf: [256]u16 = undefined;
        const at = fuzzy.positions(self.path, self.query, &buf) orelse buf[0..0];
        const name_start = if (std.mem.lastIndexOfScalar(u8, self.path, '/')) |i| i + 1 else 0;
        cx.render(ui.box(.{ .direction = .row }, .{Runs{ .path = self.path, .at = at, .name_start = name_start }}));
    }
};

const Runs = struct {
    path: []const u8,
    at: []const u16,
    name_start: usize,

    pub fn render(self: @This(), cx: *Cx) void {
        var i: usize = 0;
        var k: usize = 0;
        while (i < self.path.len) {
            const matched = k < self.at.len and self.at[k] == i;
            const in_name = i >= self.name_start;
            var j = i + 1;
            if (matched) {
                k += 1;
                while (k < self.at.len and self.at[k] == j and (j >= self.name_start) == in_name) : (j += 1) k += 1;
            } else {
                const stop = if (k < self.at.len) self.at[k] else self.path.len;
                while (j < stop and (j >= self.name_start) == in_name) j += 1;
            }
            const color = if (matched) theme.color.primary else if (in_name) theme.color.foreground else theme.color.muted;
            cx.render(ui.text(self.path[i..j], .{ .size = 13, .color = color }));
            i = j;
        }
    }
};

/// The previewed file's name.
const Title = struct {
    pub fn render(_: @This(), cx: *Cx) void {
        const s = cx.state(AppState);
        const name = s.picker.shownName();
        cx.render(ui.box(.{
            .fill_width = true,
            .height = header_height,
            .alignment = .{ .main = .center, .cross = .center },
        }, .{ui.text(name, .{ .size = 13, .weight = .semibold, .color = theme.color.foreground })}));
    }
};

const Preview = struct {
    width: f32,
    height: f32,

    pub fn render(self: @This(), cx: *Cx) void {
        const s = cx.state(AppState);
        cx.render(ui.box(.{ .padding = .{ .each = .{ .top = 8, .right = 0, .bottom = 8, .left = 0 } } }, .{
            code_style.editor(.{
                .id = "preview",
                .placeholder = s.picker.preview.message,
                .width = self.width,
                .height = self.height - 16,
                .soft_wrap = true,
                .highlighter = picker.highlighter(s),
            }),
        }));
        picker.loadPreview(s, cx.window());
    }
};
