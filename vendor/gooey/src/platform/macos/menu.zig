//! Native menus: the menu bar and context menus (NSMenu).
//!
//! A menu-bar item either sends a standard AppKit action up the responder
//! chain (`terminate:`, `hide:`…) or replays its keystroke to the key window,
//! so picking "Close" runs the same keymap binding as pressing ⌘W.

const objc = @import("objc");
const input = @import("../../input/events.zig");
const appkit = @import("appkit.zig");

pub const Item = struct {
    /// Empty draws a separator.
    title: [:0]const u8 = "",
    /// Key equivalent AppKit shows and matches, e.g. "w"; "" for none.
    key: [:0]const u8 = "",
    mods: input.Modifiers = .{ .cmd = true },
    /// Keystroke replayed to the key window when the item is picked.
    code: input.KeyCode = .unknown,
    /// A standard action instead, e.g. "terminate:".
    action: ?[:0]const u8 = null,
};

pub const Menu = struct {
    title: [:0]const u8,
    items: []const Item,
};

/// Replaces the menu bar. macOS shows the first menu under the app's name.
pub fn setMainMenu(menus: []const Menu) void {
    const bar = newMenu("");
    for (menus) |m| {
        const sub = newMenu(m.title);
        for (m.items) |it| sub.msgSend(void, "addItem:", .{newItem(it).value});
        const holder = newItem(.{ .title = m.title });
        holder.msgSend(void, "setSubmenu:", .{sub.value});
        bar.msgSend(void, "addItem:", .{holder.value});
    }
    app().msgSend(void, "setMainMenu:", .{bar.value});
}

var picked: ?usize = null;

/// Shows `titles` as a context menu at the mouse and returns the picked index.
/// It runs a nested event loop, so call it after input handling (`deferCommand`).
pub fn popUp(titles: []const [:0]const u8) ?usize {
    return popUpSelect(titles, null);
}

/// Like `popUp`, for a choice: `selected` gets a checkmark and opens under
/// the mouse, as in a pop-up button.
pub fn popUpSelect(titles: []const [:0]const u8, selected: ?usize) ?usize {
    const menu = newMenu("");
    var under: ?*anyopaque = null;
    for (titles, 0..) |t, i| {
        const it = newItem(.{ .title = t, .action = "gooeyMenuPick:" });
        it.msgSend(void, "setTag:", .{@as(c_long, @intCast(i))});
        if (selected == i) {
            it.msgSend(void, "setState:", .{@as(c_long, 1)}); // NSControlStateValueOn
            under = it.value;
        }
        menu.msgSend(void, "addItem:", .{it.value});
    }
    const NSEvent = objc.getClass("NSEvent") orelse return null;
    const at = NSEvent.msgSend(appkit.NSPoint, "mouseLocation", .{});
    picked = null;
    _ = menu.msgSend(bool, "popUpMenuPositioningItem:atLocation:inView:", .{ under, at, @as(?*anyopaque, null) });
    return picked;
}

/// The input view's `gooeyMenuPick:`: records a context-menu choice.
pub fn pick(sender: objc.Object) void {
    picked = @intCast(sender.msgSend(c_long, "tag", .{}));
}

/// The input view's `gooeyMenuKey:`: the keystroke a menu-bar item replays.
pub fn keyEvent(sender: objc.Object) input.KeyEvent {
    const mask = appkit.NSEventModifierFlags.from(sender.msgSend(c_ulong, "keyEquivalentModifierMask", .{}));
    return .{
        .key = input.KeyCode.from(@intCast(sender.msgSend(c_long, "tag", .{}))),
        .modifiers = .{ .shift = mask.shift, .ctrl = mask.control, .alt = mask.option, .cmd = mask.command },
        .characters = null,
        .characters_ignoring_modifiers = null,
        .is_repeat = false,
    };
}

fn app() objc.Object {
    const NSApplication = objc.getClass("NSApplication").?;
    return NSApplication.msgSend(objc.Object, "sharedApplication", .{});
}

fn newMenu(title: [:0]const u8) objc.Object {
    const menu = objc.getClass("NSMenu").?.msgSend(objc.Object, "alloc", .{});
    return menu.msgSend(objc.Object, "initWithTitle:", .{string(title).value});
}

fn newItem(it: Item) objc.Object {
    const NSMenuItem = objc.getClass("NSMenuItem").?;
    if (it.title.len == 0) return NSMenuItem.msgSend(objc.Object, "separatorItem", .{});
    const action: ?[:0]const u8 = it.action orelse if (it.code != .unknown) "gooeyMenuKey:" else null;
    const item = NSMenuItem.msgSend(objc.Object, "alloc", .{}).msgSend(objc.Object, "initWithTitle:action:keyEquivalent:", .{
        string(it.title).value,
        if (action) |a| objc.sel(a).value else null,
        string(it.key).value,
    });
    var mask: c_ulong = 0;
    if (it.mods.shift) mask |= 1 << 17;
    if (it.mods.ctrl) mask |= 1 << 18;
    if (it.mods.alt) mask |= 1 << 19;
    if (it.mods.cmd) mask |= 1 << 20;
    item.msgSend(void, "setKeyEquivalentModifierMask:", .{mask});
    item.msgSend(void, "setTag:", .{@as(c_long, @intFromEnum(it.code))});
    return item;
}

fn string(s: [:0]const u8) objc.Object {
    return objc.getClass("NSString").?.msgSend(objc.Object, "stringWithUTF8String:", .{s.ptr});
}
