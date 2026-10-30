//! A one-line label cut to `max_width`, its end fading into the background
//! behind it. Gooey boxes can't clip, so a gradient is drawn over the cut.

const gooey = @import("gooey");
const theme = @import("../theme.zig");

const ui = gooey.ui;
const Cx = gooey.Cx;
const Color = gooey.Color;

const fade: f32 = 24;
const fade_height: f32 = 20;

pub const FadeLabel = struct {
    text: []const u8,
    max_width: f32,
    color: Color,
    /// From `fadeTo`, with the palette color behind the label.
    paint: *const fn (*ui.DrawContext) void,

    pub fn render(self: @This(), cx: *Cx) void {
        const label = fit(cx, self.text, self.max_width);
        cx.render(ui.box(.{ .direction = .row }, .{
            ui.text(label, .{ .size = theme.ui_font_size, .color = self.color }),
            ui.when(label.len < self.text.len, .{ui.box(.{
                .floating = .{ .element_anchor = .right_center, .parent_anchor = .right_center, .z_index = 1 },
                .pointer_events = .none,
            }, .{ui.canvas(fade, fade_height, self.paint)})}),
        }));
    }
};

/// A paint function fading from transparent to the palette's `field` (read
/// as it paints, so it follows light/dark).
pub fn fadeTo(comptime field: []const u8) *const fn (*ui.DrawContext) void {
    return struct {
        fn paint(ctx: *ui.DrawContext) void {
            const bg: Color = @field(theme.color, field);
            var grad = ui.LinearGradient.horizontal(fade);
            _ = grad.addStopColor(0, bg.withAlpha(0)).addStopColor(1, bg);
            ctx.fillRectLinearGradient(0, 0, fade, fade_height, &grad);
        }
    }.paint;
}

/// The longest prefix of `text` that fits `max`, cut on a codepoint (binary search).
fn fit(cx: *Cx, text: []const u8, max: f32) []const u8 {
    if (width(cx, text) <= max) return text;
    var lo: usize = 0;
    var hi = text.len;
    while (hi - lo > 1) {
        var mid = (lo + hi) / 2;
        while (mid > lo and text[mid] & 0xc0 == 0x80) mid -= 1;
        if (mid == lo) break;
        if (width(cx, text[0..mid]) <= max) lo = mid else hi = mid;
    }
    return text[0..lo];
}

fn width(cx: *Cx, text: []const u8) f32 {
    const m = cx.measureText(text, .{ .font_size = theme.ui_font_size }) catch return 0;
    return m.width;
}
