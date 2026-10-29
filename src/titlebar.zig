//! Where the titlebar row's buttons start: past the traffic lights (Onyx's
//! `pl(84)`), or at the container's edge in full screen, where AppKit hides them.

const gooey = @import("gooey");
const theme = @import("theme.zig");

const lights: f32 = 84;
const full_screen_mask: u64 = 1 << 14;

pub fn left(g: *gooey.Window) f32 {
    const pw = g.platform_window orelse return lights;
    return if (pw.ns_window.msgSend(u64, "styleMask", .{}) & full_screen_mask != 0) theme.inset else lights;
}
