//! The welcome screen, shown while no folder is open: the logo, then a card
//! with Open Folder… and the folders opened before.

const std = @import("std");
const gooey = @import("gooey");
const components = @import("gooey-components");
const theme = @import("theme.zig");
const AppState = @import("state.zig").AppState;
const workspace = @import("tree/workspace.zig");
const fade_label = @import("ui/fade_label.zig");
const clickable = @import("ui/clickable.zig");

const ui = gooey.ui;
const Cx = gooey.Cx;
const Svg = components.Svg;
const Image = components.Image;
const Lucide = components.Lucide;

/// The embedded logo's image source name (`gooey.image.loader.embedded`).
pub const logo = "zikky:logo";
/// The home folder, shown as ~ in the recent folders' paths.
pub var home: []const u8 = "";

const card_width: f32 = 440;
const row_height: f32 = 34;
const row_pad: f32 = 10;
const icon_slot: f32 = 26;

pub const Welcome = struct {
    width: f32,
    height: f32,

    pub fn render(self: @This(), cx: *Cx) void {
        const s = cx.state(AppState);
        cx.render(ui.box(.{
            .width = self.width,
            .height = self.height,
            .alignment = .{ .main = .center, .cross = .center },
            .gap = 6,
        }, .{
            Image{ .src = logo, .size = 96, .alt = "Zikky" },
            ui.box(.{ .height = 6 }, .{}),
            ui.text("Zikky", .{ .size = 24, .weight = .bold, .color = theme.color.foreground }),
            ui.text("Open a folder to start", .{ .size = 13, .color = theme.color.muted }),
            ui.box(.{ .height = 22 }, .{}),
            ui.box(.{
                .width = card_width,
                .background = theme.color.background,
                .corner_radius = theme.radius_lg,
                .border_width = .{ .all = 1 },
                .border_color = theme.color.border.withAlpha(0.8),
                .shadow = theme.shadow_xs,
                .padding = .{ .all = 6 },
            }, .{
                Row{ .icon = Lucide.folder_open, .label = "Open Folder…", .hint = "⇧⌘O", .on_click = cx.command(workspace.openFolder) },
                ui.when(s.recent_count > 0, .{
                    ui.box(.{ .fill_width = true, .padding = .{ .each = .{ .top = 6, .right = 4, .bottom = 6, .left = 4 } } }, .{
                        ui.box(.{ .fill_width = true, .height = 1, .background = theme.color.border }, .{}),
                    }),
                    ui.box(.{ .fill_width = true, .padding = .{ .each = .{ .top = 2, .right = row_pad, .bottom = 4, .left = row_pad } } }, .{
                        ui.text("Recent", .{ .size = 12, .weight = .semibold, .color = theme.color.muted }),
                    }),
                }),
                Recent{ .s = s },
            }),
        }));
    }
};

const Recent = struct {
    s: *AppState,

    pub fn render(self: @This(), cx: *Cx) void {
        for (self.s.recent[0..self.s.recent_count], 0..) |path, i| {
            cx.render(Row{
                .icon = Lucide.folder,
                .label = std.fs.path.basename(path),
                .path = tilde(&shown[i], std.fs.path.dirname(path) orelse path),
                .on_click = cx.commandWith(@as(u8, @intCast(i)), workspace.openRecent),
            });
        }
    }
};

/// One clickable line: an icon, a label, then a hint at the right or the
/// folder's location after it (cut to fit).
const Row = struct {
    icon: []const u8,
    label: []const u8,
    hint: []const u8 = "",
    path: []const u8 = "",
    on_click: ui.HandlerRef,

    pub fn render(self: @This(), cx: *Cx) void {
        const label_w = (cx.measureText(self.label, .{ .font_size = theme.ui_font_size }) catch return).width;
        // The card's inner width less the row's padding, icon and the gap before the path.
        const room = card_width - 2 - 12 - 2 * row_pad - icon_slot - label_w - 10;
        cx.render(clickable.box(.{ .hover = theme.color.sidebar_accent.withAlpha(0.65), .on_click = self.on_click }, .{
            .fill_width = true,
            .height = row_height,
            .direction = .row,
            .alignment = .{ .cross = .center },
            .padding = .{ .each = .{ .top = 0, .right = row_pad, .bottom = 0, .left = row_pad } },
            .corner_radius = theme.radius,
        }, .{
            ui.box(.{ .width = icon_slot, .alignment = .{ .cross = .center } }, .{
                Svg{ .path = self.icon, .size = 15, .no_fill = true, .stroke_color = theme.color.muted, .stroke_width = 15.0 / 12.0 },
            }),
            ui.text(self.label, .{ .size = theme.ui_font_size, .color = theme.color.foreground }),
            ui.box(.{ .width = 10 }, .{}),
            ui.when(self.path.len > 0 and room > 24, .{fade_label.FadeLabel{
                .text = self.path,
                .max_width = room,
                .color = theme.color.muted,
                .paint = fade_label.fadeTo("background"),
            }}),
            ui.box(.{ .grow_width = true }, .{}),
            ui.when(self.hint.len > 0, .{ui.text(self.hint, .{ .size = 13, .color = theme.color.muted })}),
        }));
    }
};

var shown: [@import("state.zig").max_recent][1024]u8 = undefined;

/// `path` with the home folder written as ~ (in `buf`).
fn tilde(buf: []u8, path: []const u8) []const u8 {
    if (home.len == 0 or !std.mem.startsWith(u8, path, home)) return path;
    return std.fmt.bufPrint(buf, "~{s}", .{path[home.len..]}) catch path;
}
