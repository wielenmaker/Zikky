//! App state: the file tree of the opened folder and the open tabs.

const std = @import("std");
const gooey = @import("gooey");
const theme = @import("theme.zig");
const fs_tree = @import("fs_tree.zig");
const editor_font = @import("editor_font.zig");
const row_menu = @import("row_menu.zig");
const tabs = @import("tabs.zig");
const picker = @import("picker.zig");
const find = @import("find.zig");
const palette = @import("palette.zig");
const store = @import("store.zig");
const vim = @import("vim.zig");
const Settings = @import("settings.zig").Settings;
const settings_panes = @import("settings_panes.zig");
const appearance = @import("appearance.zig");
const terminal = @import("terminal.zig");
const keys = @import("keys.zig");

const TreeListState = gooey.widgets.TreeListState;
const CodeEditorState = gooey.widgets.CodeEditorState;
const max_nodes = gooey.widgets.tree_list.MAX_TREE_NODES;
pub const max_recent = 8;

pub const AppState = struct {
    tree: TreeListState = TreeListState.initWithIndent(theme.row_height, theme.indent),
    names: [max_nodes][]const u8 = undefined,
    paths: [max_nodes][]const u8 = undefined,
    /// Folder shown in the tree; names and paths live in `arena`. Empty: none
    /// is open, and the window shows the welcome screen.
    root: []const u8 = ".",
    /// Folders opened before, newest first (the welcome screen's list).
    recent: [max_recent][]const u8 = undefined,
    recent_count: u8 = 0,
    arena: std.mem.Allocator = undefined,
    tabs: tabs.Tabs = .{},
    settings: Settings = .{},
    /// The main window; the settings window acts on it.
    main: *gooey.Window = undefined,
    settings_pane: u8 = 0,
    settings_query: []const u8 = "",
    /// The excluded-folders field while it is edited; applied when it loses focus.
    exclude_edit: []const u8 = "",
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
    /// The terminal with no tab open (each tab has its own).
    term_bare: terminal.Slot = .{},
    /// Keys go to the shown terminal.
    term_focus: bool = false,
    term_height: f32 = 260,
    /// Where the terminal was drawn, and whether the gap above it is being dragged.
    term_rect: terminal.Rect = .{},
    term_drag: bool = false,

    /// The opened folder is the tree's one root, expanded, with its contents under it.
    pub fn load(self: *AppState, io: std.Io) void {
        if (self.welcome()) return;
        const full = std.Io.Dir.realPathFileAlloc(.cwd(), io, self.root, self.arena) catch self.root;
        const top = self.add(null, std.fs.path.basename(full), full, true) orelse return;
        fs_tree.addDir(self, io, self.root, top);
        self.tree.expandNode(top);
        self.tree.rebuild();
    }

    /// The sidebar's +: picks a folder and shows it in place of the current one. The
    /// panel runs a nested event loop, so it waits until the click is handled.
    pub fn openFolder(_: *AppState, g: *gooey.Window) void {
        g.deferCommand(promptFolder);
    }

    fn promptFolder(self: *AppState, g: *gooey.Window) void {
        const picked = gooey.file_dialog.promptForPaths(self.arena, .{ .directories = true, .files = false, .prompt = "Open" }) orelse return;
        defer picked.deinit();
        if (picked.paths.len == 0) return;
        self.openRoot(g, self.arena.dupe(u8, picked.paths[0]) catch return);
    }

    /// No folder is open: the window shows the welcome screen.
    pub fn welcome(self: *const AppState) bool {
        return self.root.len == 0;
    }

    /// A folder in the welcome screen's recent list; one that is gone leaves the list.
    pub fn openRecent(self: *AppState, g: *gooey.Window, i: u8) void {
        if (i >= self.recent_count) return;
        if (std.Io.Dir.access(.cwd(), g.io, self.recent[i], .{})) {
            self.openRoot(g, self.recent[i]);
        } else |_| {
            std.mem.copyForwards([]const u8, self.recent[i .. self.recent_count - 1], self.recent[i + 1 .. self.recent_count]);
            self.recent_count -= 1;
        }
    }

    /// Shows `path` in the tree in place of the current folder.
    pub fn openRoot(self: *AppState, g: *gooey.Window, path: []const u8) void {
        self.root = path;
        self.closeAll(g);
        self.tree.clear();
        self.load(g.io);
        if (self.tree.node_count > 0) self.remember(self.paths[0]);
    }

    /// Moves `path` to the front of the recent folders.
    pub fn remember(self: *AppState, path: []const u8) void {
        var n: u8 = 0;
        for (self.recent[0..self.recent_count]) |p| {
            if (!std.mem.eql(u8, p, path) and n < max_recent - 1) {
                self.recent[n] = p;
                n += 1;
            }
        }
        std.mem.copyBackwards([]const u8, self.recent[1 .. n + 1], self.recent[0..n]);
        self.recent[0] = path;
        self.recent_count = n + 1;
    }

    pub fn toggleSidebar(self: *AppState, _: *gooey.Window) void {
        self.sidebar_open = !self.sidebar_open;
    }

    pub fn openPicker(self: *AppState, g: *gooey.Window) void {
        find.close(self, g);
        if (self.palette.open) palette.close(self, g);
        picker.open(self, g);
    }

    pub fn selectPane(self: *AppState, _: *gooey.Window, pane: u8) void {
        self.settings_pane = pane;
        self.settings_query = "";
    }

    pub fn prevPane(self: *AppState, _: *gooey.Window) void {
        self.settings_pane -|= 1;
    }

    pub fn nextPane(self: *AppState, _: *gooey.Window) void {
        self.settings_pane = @min(self.settings_pane + 1, settings_panes.panes.len - 1);
    }

    pub fn flipSetting(self: *AppState, _: *gooey.Window, sw: Settings.Switch) void {
        self.settings.flip(sw);
        self.saveSettings(self.main);
        switch (sw) {
            .vim_mode => self.applyVim(self.main),
            .show_hidden => self.reloadTree(self.main),
            else => {},
        }
        self.main.requestRender();
    }

    pub fn applyExclude(self: *AppState, _: *gooey.Window) void {
        if (std.mem.eql(u8, self.exclude_edit, self.settings.exclude)) return;
        self.settings.exclude = self.arena.dupe(u8, self.exclude_edit) catch return;
        self.saveSettings(self.main);
        self.reloadTree(self.main);
        self.main.requestRender();
    }

    pub fn zoomIn(self: *AppState, g: *gooey.Window) void {
        self.setFontSize(g, self.settings.font_size + 1);
    }

    pub fn zoomOut(self: *AppState, g: *gooey.Window) void {
        self.setFontSize(g, self.settings.font_size - 1);
    }

    pub fn zoomReset(self: *AppState, g: *gooey.Window) void {
        self.setFontSize(g, theme.mono_font_size);
    }

    pub fn setFontSize(self: *AppState, g: *gooey.Window, size: f32) void {
        self.settings.font_size = editor_font.load(g.resources.text_system, self.settings.font, size);
        self.measureCell(g);
        self.saveSettings(g);
        self.main.requestRender();
    }

    /// Loads the editor font, measuring its line height at the default size first.
    pub fn applyFont(self: *AppState, g: *gooey.Window) void {
        const ts = g.resources.text_system;
        _ = editor_font.load(ts, self.settings.font, theme.mono_font_size);
        self.line_height = editor_font.lineHeight(ts);
        self.settings.font_size = editor_font.load(ts, self.settings.font, self.settings.font_size);
        self.measureCell(g);
    }

    fn measureCell(self: *AppState, g: *gooey.Window) void {
        const ts = g.resources.text_system;
        self.cell_h = @ceil(editor_font.lineHeight(ts));
        self.cell_w = editor_font.cellWidth(ts);
    }

    /// The font control: a menu of the families. Deferred: it runs a nested event loop.
    pub fn pickFont(_: *AppState, g: *gooey.Window) void {
        g.deferCommand(showFontMenu);
    }

    fn showFontMenu(self: *AppState, g: *gooey.Window) void {
        const mac = gooey.platform.macos;
        const i = mac.menu.popUpSelect(&editor_font.family_names, editor_font.indexOf(self.settings.font)) orelse return;
        self.settings.font = editor_font.families[i].name;
        self.applyFont(g);
        self.saveSettings(g);
        self.main.requestRender();
        g.requestRender();
    }

    pub fn setAppearance(self: *AppState, g: *gooey.Window, mode: Settings.Appearance) void {
        self.settings.appearance = mode;
        appearance.apply(mode);
        self.saveSettings(g);
        self.main.requestRender();
        g.requestRender();
    }

    pub fn saveSettings(self: *AppState, g: *gooey.Window) void {
        store.save(g.io, Settings.file, self.settings);
    }

    /// Keys and clicks go through `keys.capture` (quick open, the terminal,
    /// the find bar, vim) before the focused widget.
    pub fn applyVim(_: *AppState, g: *gooey.Window) void {
        g.key_capture = keys.capture;
    }

    /// Rebuilds the tree after a setting that filters it changed.
    pub fn reloadTree(self: *AppState, g: *gooey.Window) void {
        self.tree.clear();
        self.load(g.io);
        self.closeAll(g);
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

    pub fn onRowClick(self: *AppState, g: *gooey.Window, entry_index: u32) void {
        const e = self.tree.getEntry(entry_index) orelse return;
        if (row_menu.isMenuClick(g)) return g.deferCommandWith(e.node_index, row_menu.show);
        if (e.is_folder) return self.tree.toggleExpand(entry_index);
        self.openNode(g, e.node_index);
    }

    /// The shown file's node; its row gets the active pill, like Onyx.
    pub fn active(self: *const AppState) ?u32 {
        return if (self.tabs.count == 0) null else self.tabs.list[self.tabs.current].node;
    }

    /// The shown editor.
    pub fn editor(self: *AppState, g: *gooey.Window) ?*CodeEditorState {
        return tabs.editor(g, if (self.tabs.active()) |t| t.id() else tabs.empty_id);
    }

    /// Opens a file node in the current tab (or shows its tab if it has one).
    pub fn openNode(self: *AppState, g: *gooey.Window, node: u32) void {
        if (self.tabs.find(node)) |i| return self.selectTab(g, i);
        const t = self.tabs.active() orelse return self.openInNewTab(g, node);
        self.tabs.leave(g);
        tabs.load(t, g, node, self.paths[node]);
    }

    /// Opens a file node in a tab of its own (the current one when all are taken).
    pub fn openInNewTab(self: *AppState, g: *gooey.Window, node: u32) void {
        if (self.tabs.find(node)) |i| return self.selectTab(g, i);
        self.tabs.leave(g);
        if (self.tabs.add(g, node, self.paths[node])) |i| self.tabs.current = i else tabs.load(self.tabs.active().?, g, node, self.paths[node]);
    }

    pub fn selectTab(self: *AppState, g: *gooey.Window, i: u8) void {
        if (i == self.tabs.current or i >= self.tabs.count) return;
        self.tabs.leave(g);
        self.tabs.current = i;
    }

    /// A tab's ×.
    pub fn closeTab(self: *AppState, g: *gooey.Window, i: u8) void {
        if (i == self.tabs.current) self.tabs.leave(g);
        self.tabs.remove(g, i);
    }

    /// ⌘W: closes the shown tab.
    pub fn close(self: *AppState, g: *gooey.Window) void {
        if (self.tabs.count > 0) self.closeTab(g, self.tabs.current);
    }

    fn closeAll(self: *AppState, g: *gooey.Window) void {
        while (self.tabs.count > 0) self.tabs.remove(g, self.tabs.count - 1);
        terminal.end(&self.term_bare);
        self.term_focus = false;
    }

    pub fn toggleTerminal(self: *AppState, g: *gooey.Window) void {
        terminal.toggle(self, g);
    }
};
