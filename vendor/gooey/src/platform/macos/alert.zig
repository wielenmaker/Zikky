//! A modal NSAlert with a message and buttons.

const objc = @import("objc");

fn string(s: [:0]const u8) objc.c.id {
    const NSString = objc.getClass("NSString").?;
    return NSString.msgSend(objc.c.id, "stringWithUTF8String:", .{s.ptr});
}

/// Returns the index of the clicked button; the first is the default.
/// It runs a nested event loop, so call it after input handling (`deferCommand`).
pub fn ask(message: [:0]const u8, info: [:0]const u8, buttons: []const [:0]const u8) ?usize {
    const NSAlert = objc.getClass("NSAlert") orelse return null;
    const alert = NSAlert.msgSend(objc.Object, "new", .{});
    alert.msgSend(void, "setMessageText:", .{string(message)});
    alert.msgSend(void, "setInformativeText:", .{string(info)});
    for (buttons) |b| _ = alert.msgSend(objc.c.id, "addButtonWithTitle:", .{string(b)});
    const first = 1000; // NSAlertFirstButtonReturn
    const clicked = alert.msgSend(c_long, "runModal", .{});
    return if (clicked < first) null else @intCast(clicked - first);
}
