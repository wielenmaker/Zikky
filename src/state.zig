//! App state: the opened folder's tree, the open tabs and what each panel
//! shows. What acts on it lives with each feature (`workspace`, `tab_actions`,
//! `settings_actions`, `font_actions`, ...).

const std = @import("std");
const gooey = @import("gooey");
const theme = @import("theme.zig");
const tabs = @import("editor/tabs.zig");
const picker = @import("overlays/picker.zig");
const find = @import("editor/find.zig");
const palette = @import("overlays/palette.zig");
const terminal = @import("terminal/terminal.zig");
const Settings = @import("settings/settings.zig").Settings;
const shortcuts = @import("shortcuts/shortcuts.zig");
const workspace = @import("tree/workspace.zig");

const TreeListState = gooey.widgets.TreeListState;
const CodeEditorState = gooey.widgets.CodeEditorState;
const max_nodes = gooey.widgets.tree_list.MAX_TREE_NODES;

pub const AppState = struct {
    tree: TreeListState = TreeListState.initWithIndent(theme.row_height, theme.indent),
    names: [max_nodes][]const u8 = undefined,
    paths: [max_nodes][]const u8 = undefined,
    /// Folder shown in the tree; names and paths live in `arena`. Empty: none
    /// is open, and the window shows just the editor.
    root: []const u8 = ".",
    arena: std.mem.Allocator = undefined,
    tabs: tabs.Tabs = .{},
    settings: Settings = .{},
    /// The main window; the settings window acts on it.
    main: *gooey.Window = undefined,
    settings_pane: u8 = 0,
    settings_query: []const u8 = "",
    /// The excluded-folders field while it is edited; applied when it loses focus.
    exclude_edit: []const u8 = "",
    /// The shortcut taking new keys (Settings › Keyboard).
    recording: ?shortcuts.Id = null,
    /// Quick open (⌘O / ⌘P).
    picker: picker.Picker = .{},
    /// The command palette (⌘⇧P).
    palette: palette.Palette = .{},
    /// The find bar (⌘F, vim's `/`).
    find: find.Find = .{},
    /// Hidden with ⌘\ or the panel buttons; the editor then fills the window.
    sidebar_open: bool = true,
    /// Editor line height at the default size, read at start; the tree's
    /// first row is centred on the editor's first line with it.
    line_height: f32 = 0,
    /// A terminal cell at the editor font's current size.
    cell_w: f32 = 8,
    cell_h: f32 = 16,
    /// The terminal panel (⌘J).
    term: terminal.Panel = .{},

    /// No folder is open: the sidebar stays shut, with nothing to show.
    pub fn noFolder(self: *const AppState) bool {
        return self.root.len == 0;
    }

    pub fn toggleSidebar(self: *AppState, g: *gooey.Window) void {
        if (self.noFolder()) return g.deferCommand(workspace.askFolder);
        self.sidebar_open = !self.sidebar_open;
    }

    /// A node's path from the opened folder; "." for the folder itself (node 0).
    pub fn relativePath(self: *const AppState, node: u32) []const u8 {
        const path = self.paths[node];
        if (node == 0 or !std.mem.startsWith(u8, path, self.root)) return ".";
        return std.mem.trimStart(u8, path[self.root.len..], "/");
    }

    /// Adds a node; null once the tree is full.
    pub fn add(self: *AppState, parent: ?u32, name: []const u8, path: []const u8, is_folder: bool) ?u32 {
        const idx = (if (parent) |p| self.tree.addChild(p, is_folder) else self.tree.addRoot(is_folder)) orelse return null;
        self.names[idx] = name;
        self.paths[idx] = path;
        return idx;
    }

    /// The shown file's node; its row gets the active pill, like Onyx.
    pub fn active(self: *const AppState) ?u32 {
        return if (self.tabs.count == 0) null else self.tabs.list[self.tabs.current].node;
    }

    pub fn tabName(self: *const AppState, t: *const tabs.Tab) []const u8 {
        return if (t.node == tabs.untitled) "Untitled" else self.names[t.node];
    }

    /// The shown editor.
    pub fn editor(self: *AppState, g: *gooey.Window) ?*CodeEditorState {
        return tabs.editor(g, if (self.tabs.active()) |t| t.id() else tabs.empty_id);
    }
};
