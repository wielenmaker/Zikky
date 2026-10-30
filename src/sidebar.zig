//! Left sidebar: the traffic lights and hide button, then the file tree.
//! Row geometry mirrors Onyx's `file_tree.rs`.

const gooey = @import("gooey");
const components = @import("gooey-components");
const theme = @import("theme.zig");
const titlebar = @import("titlebar.zig");
const AppState = @import("state.zig").AppState;
const workspace = @import("workspace.zig");
const file_kind = @import("file_kind.zig");
const IconButton = @import("icon_button.zig").IconButton;
const FileIcon = @import("file_icon.zig").FileIcon;
const fade_label = @import("fade_label.zig");
const rename = @import("rename.zig");
const clickable = @import("clickable.zig");
const row_menu = @import("row_menu.zig");
const tab_actions = @import("tab_actions.zig");

const ui = gooey.ui;
const Cx = gooey.Cx;
const Color = gooey.Color;
const TreeEntry = gooey.widgets.TreeEntry;
const Lucide = components.Lucide;

/// Shows or hides the sidebar (⌘\, like Onyx).
pub const ToggleSidebar = struct {};

pub fn bindKeys(g: *gooey.Window) void {
    g.keymap().bind(ToggleSidebar, "cmd-\\", null);
}

pub const Sidebar = struct {
    pub fn render(_: @This(), cx: *Cx) void {
        const s = cx.state(AppState);
        cx.render(ui.box(.{
            .width = theme.sidebar_width,
            .grow_height = true,
        }, .{ Header{}, TreeView{ .s = s } }));
    }
};

/// The titlebar row: traffic lights, the hide button (Onyx's `pl(84)`), and + at the
/// right edge to open another folder.
const Header = struct {
    pub fn render(_: @This(), cx: *Cx) void {
        cx.render(ui.box(.{
            .fill_width = true,
            .height = theme.titlebar_height,
            .direction = .row,
            .alignment = .{ .cross = .center },
            .padding = .{ .each = .{ .top = 0, .right = 10, .bottom = 0, .left = titlebar.left(cx.window()) } },
        }, .{
            IconButton{ .icon = Lucide.panel_left_close, .on_click = cx.command(AppState.toggleSidebar) },
            ui.box(.{ .grow_width = true }, .{}),
            IconButton{ .icon = Lucide.plus, .on_click = cx.command(workspace.openFolder) },
        }));
    }
};

const TreeView = struct {
    s: *AppState,

    pub fn render(self: @This(), cx: *Cx) void {
        // First row's label centred on the editor's first line at the default size:
        // the container's border and top padding plus half a line, less half a row.
        const top = 1 + theme.editor_top + self.s.line_height / 2 - theme.row_height / 2;
        cx.lists.tree("file-tree", &self.s.tree, .{
            .fill_width = true,
            .grow_height = true,
            .padding = .{ .each = .{ .top = @max(0, top), .right = 0, .bottom = 4, .left = 0 } },
            .indent_px = theme.indent,
            // It scrolls without a bar, like Onyx's tree.
            .scrollbar_size = 0,
            .track_color = Color.transparent,
            .thumb_color = Color.transparent,
        }, Row.render);
        rename.focusField(cx.window());
    }
};

/// Room for a depth-0 label: the sidebar less the row's padding (13 + 8, 1 + 9)
/// and the chevron and icon slots (16 + 20).
const label_width = theme.sidebar_width - 13 - 8 - 1 - 9 - 16 - 20;

const Row = struct {
    fn render(entry: *const TreeEntry, cx: *Cx) void {
        const s = cx.stateConst(AppState);
        const index = indexOf(s, entry);
        const active = s.active() == entry.node_index;
        const look = Look.of(s, entry, active);
        const renaming = rename.node == entry.node_index;
        const width = label_width - theme.indent * @as(f32, @floatFromInt(entry.depth));

        // Outer line: 8px side margins, then 4px + 1px so guides sit under chevrons.
        cx.render(ui.box(.{
            .fill_width = true,
            .height = theme.row_height,
            .direction = .row,
            .padding = .{ .each = .{ .top = 0, .right = 8, .bottom = 0, .left = 13 } },
        }, .{
            Guides{ .depth = entry.depth },
            clickable.box(.{
                .fill = if (active) theme.color.background else Color.transparent,
                .hover = if (active) null else theme.color.sidebar_accent.withAlpha(0.65),
                .on_click = cx.commandWith(index, onRowClick),
            }, .{
                .grow_width = true,
                .height = theme.row_height,
                .direction = .row,
                .alignment = .{ .cross = .center },
                // GPUI borders take layout space; gooey's don't, so pad by the 1px border.
                .padding = .{ .each = .{ .top = 1, .right = 9, .bottom = 1, .left = 1 } },
                .corner_radius = theme.radius,
                .border_width = .{ .all = 1 },
                .border_color = if (active) theme.color.border.withAlpha(0.7) else Color.transparent,
                .shadow = if (active) theme.shadow_xs else null,
            }, .{
                Icon{ .kind = .{ .icon = chevron(entry), .color = theme.color.muted }, .size = 12, .slot = 16, .center = true },
                Icon{ .kind = look.kind, .size = 14, .slot = 20, .center = false },
                ui.when(renaming, .{ui.input(rename.input_id, .{
                    .bind = &rename.text,
                    .width = width,
                    .height = 22,
                    .padding = 3,
                    .corner_radius = 5,
                    .background = theme.color.background,
                    .border_color = theme.color.border,
                    .border_color_focused = theme.color.primary,
                    .text_color = theme.color.foreground,
                    .cursor_color = theme.color.primary,
                    .selection_color = theme.color.primary.withAlpha(0.18),
                    .on_blur_handler = cx.command(rename.cancel),
                })}),
                ui.when(!renaming, .{fade_label.FadeLabel{
                    .text = s.names[entry.node_index],
                    .max_width = width,
                    .color = look.label_color,
                    .paint = if (active) fade_label.fadeTo("background") else fade_label.fadeTo("sidebar_bg"),
                }}),
            }),
        }));
    }

    fn indexOf(s: *const AppState, entry: *const TreeEntry) u32 {
        return @intCast((@intFromPtr(entry) - @intFromPtr(&s.tree.entries[0])) / @sizeOf(TreeEntry));
    }

    fn chevron(e: *const TreeEntry) []const u8 {
        if (!e.is_folder) return "";
        return if (e.is_expanded) Lucide.chevron_down else Lucide.chevron_right;
    }

};

/// A row's icon and colors: folders stay muted; files take their kind's
/// icon and color, and the open file's label is darkest, like Onyx.
const Look = struct {
    kind: file_kind.Kind,
    label_color: Color,

    fn of(s: *const AppState, e: *const TreeEntry, active: bool) Look {
        if (e.is_folder) return .{
            .kind = .{ .icon = if (e.is_expanded) Lucide.folder_open else Lucide.folder, .color = theme.color.muted },
            .label_color = theme.color.sidebar_fg,
        };
        const kind = file_kind.of(s.names[e.node_index]);
        return .{
            .kind = kind,
            .label_color = if (active) theme.color.foreground else if (kind.dim) theme.color.muted else theme.color.sidebar_fg,
        };
    }
};

/// One 16px column per depth level, with a 1px guide pinned under the parent's chevron.
const Guides = struct {
    depth: u8,

    pub fn render(self: @This(), cx: *Cx) void {
        for (0..self.depth) |_| {
            cx.render(ui.box(.{
                .width = theme.indent,
                .height = theme.row_height,
                .padding = .{ .each = .{ .top = 0, .right = 0, .bottom = 0, .left = 8 } },
            }, .{
                ui.box(.{ .width = 1, .height = theme.row_height, .background = theme.color.sidebar_border }, .{}),
            }));
        }
    }
};

/// A Lucide icon in a fixed-width slot, so labels line up.
/// Stroke matches Lucide's 2-unit stroke on its 24-unit grid.
const Icon = struct {
    kind: file_kind.Kind,
    size: f32,
    slot: f32,
    center: bool,

    pub fn render(self: @This(), cx: *Cx) void {
        cx.render(ui.box(.{
            .width = self.slot,
            .height = theme.row_height - 2,
            .alignment = .{ .main = .center, .cross = if (self.center) .center else .start },
        }, .{
            ui.when(self.kind.icon.len > 0, .{FileIcon{ .kind = self.kind, .size = self.size }}),
        }));
    }
};

fn onRowClick(s: *AppState, g: *gooey.Window, entry_index: u32) void {
    const e = s.tree.getEntry(entry_index) orelse return;
    if (row_menu.isMenuClick(g)) return g.deferCommandWith(e.node_index, row_menu.show);
    if (rename.node == e.node_index) return;
    if (e.is_folder) return s.tree.toggleExpand(entry_index);
    tab_actions.open(s, g, e.node_index);
}
