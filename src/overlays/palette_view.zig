//! The command palette on screen: a rounded card floating at the top centre
//! (no dimming) with the query field, the commands and a footer of key hints.

const gooey = @import("gooey");
const components = @import("gooey-components");
const theme = @import("../theme.zig");
const AppState = @import("../state.zig").AppState;
const card = @import("../ui/card.zig");
const field = @import("../ui/field.zig");
const palette = @import("palette.zig");
const clickable = @import("../ui/clickable.zig");

const ui = gooey.ui;
const Cx = gooey.Cx;
const Color = gooey.Color;
const Svg = components.Svg;
const Lucide = components.Lucide;

const width: f32 = 420;
// Corner radii: the card (like macOS 27's window corners), the search pill, the selected row.
const card_radius: f32 = 20;
const pill_radius: f32 = 12;
const row_radius: f32 = 12;
const top: f32 = 56;
const pad: f32 = 8;
const query_height: f32 = 36;
const footer_height: f32 = 34;
/// The query block: the pill and its padding.
const query_block: f32 = query_height + 2 * pad;
const max_rows: u32 = 10;

pub const PaletteView = struct {
    window_width: f32,
    window_height: f32,

    pub fn render(self: @This(), cx: *Cx) void {
        const s = cx.state(AppState);
        palette.refresh(s);
        const rows: f32 = @floatFromInt(@min(@max(s.palette.count, 1), max_rows));
        const list_height = rows * palette.row_height + 2 * pad;
        // Border, query block, list, divider, footer.
        const height = 2 + query_block + list_height + 1 + footer_height;
        // A click outside closes it.
        cx.render(ui.box(.{
            .width = self.window_width,
            .height = self.window_height,
            .floating = .{ .z_index = 200 },
            .on_click_handler = cx.command(palette.close),
        }, .{}));
        cx.render(card.box(.{
            .width = width,
            .height = height,
            .corner_radius = card_radius,
            .floating = ui.Floating{ .element_anchor = .center_top, .parent_anchor = .center_top, .offset_y = top, .z_index = 201 },
        }, .{
            Query{},
            List{ .height = list_height },
            card.Divider{},
            Footer{},
        }));
    }
};

/// The search pill: a magnifier and the query field.
const Query = struct {
    pub fn render(_: @This(), cx: *Cx) void {
        const p = &cx.state(AppState).palette;
        cx.render(ui.box(.{ .fill_width = true, .padding = .{ .all = pad } }, .{
            ui.box(.{
                .fill_width = true,
                .height = query_height,
                .direction = .row,
                .alignment = .{ .cross = .center },
                .padding = .{ .symmetric = .{ .x = 12, .y = 0 } },
                .gap = 8,
                .corner_radius = pill_radius,
                .background = theme.color.settings.search_bg,
            }, .{
                Svg{ .path = Lucide.search, .size = 15, .no_fill = true, .stroke_color = theme.color.foreground, .stroke_width = 1.8 },
                field.bare(palette.query_id, .{ .bind = &p.query, .placeholder = if (p.sub) |c| c.title else "Search commands" }),
            }),
        }));
        if (p.focus_query) {
            p.focus_query = false;
            cx.window().focusWidget(palette.query_id);
        }
    }
};

const List = struct {
    height: f32,

    pub fn render(self: @This(), cx: *Cx) void {
        const p = &cx.state(AppState).palette;
        cx.lists.uniform("palette-list", &p.list, .{
            .fill_width = true,
            .height = self.height,
            .padding = .{ .all = pad },
            .thumb_color = theme.color.scrollbar,
            .scrollbar_size = 6,
        }, Row.render);
    }
};

const Row = struct {
    fn render(index: u32, cx: *Cx) void {
        const p = &cx.state(AppState).palette;
        const c = p.at(index);
        cx.render(clickable.box(.{
            .fill = if (index == p.selected) theme.color.sidebar_accent else Color.transparent,
            .on_click = cx.commandWith(index, palette.pick),
        }, .{
            .fill_width = true,
            .height = palette.row_height,
            .direction = .row,
            .alignment = .{ .cross = .center },
            .padding = .{ .symmetric = .{ .x = 10, .y = 0 } },
            .gap = 8,
            .corner_radius = row_radius,
        }, .{
            ui.box(.{ .grow_width = true }, .{ui.text(c.title, .{ .size = 14, .color = theme.color.foreground })}),
            ui.text(c.keys, .{ .size = 12, .color = theme.color.muted }),
            ui.when(c.children.len > 0, .{
                Svg{ .path = Lucide.chevron_right, .size = 15, .no_fill = true, .stroke_color = theme.color.muted, .stroke_width = 1.8 },
            }),
        }));
    }
};

/// Key hints, right-aligned: Back (in a submenu) and Action.
const Footer = struct {
    pub fn render(_: @This(), cx: *Cx) void {
        const in_sub = cx.state(AppState).palette.sub != null;
        cx.render(ui.box(.{
            .fill_width = true,
            .height = footer_height,
            .direction = .row,
            .alignment = .{ .main = .end, .cross = .center },
            .padding = .{ .symmetric = .{ .x = 12, .y = 0 } },
            .gap = 14,
        }, .{
            ui.when(in_sub, .{Hint{ .label = "Back", .key = "esc" }}),
            Hint{ .label = "Action", .key = "↩" },
        }));
    }
};

const Hint = struct {
    label: []const u8,
    key: []const u8,

    pub fn render(self: @This(), cx: *Cx) void {
        cx.render(ui.box(.{ .direction = .row, .alignment = .{ .cross = .center }, .gap = 6 }, .{
            ui.text(self.label, .{ .size = 12, .color = theme.color.muted }),
            ui.box(.{
                .height = 20,
                .alignment = .{ .main = .center, .cross = .center },
                .padding = .{ .symmetric = .{ .x = 7, .y = 0 } },
                .corner_radius = 5,
                .border_width = .{ .all = 1 },
                .border_color = theme.color.border,
            }, .{ui.text(self.key, .{ .size = 11, .color = theme.color.muted })}),
        }));
    }
};
