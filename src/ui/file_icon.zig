//! A file's icon: its language mark, filled (`file_marks.zig`), or else its
//! kind's Lucide outline. Used by the tree, quick open and the tab logo.

const gooey = @import("gooey");
const components = @import("gooey-components");
const file_kind = @import("file_kind.zig");

const ui = gooey.ui;
const Cx = gooey.Cx;
const Color = gooey.Color;
const Svg = components.Svg;

pub const FileIcon = struct {
    kind: file_kind.Kind,
    size: f32,
    /// Overrides the kind's color (white on the tab logo).
    color: ?Color = null,

    pub fn render(self: @This(), cx: *Cx) void {
        const color = self.color orelse self.kind.color;
        if (self.kind.mark) {
            // Marks fill their grid; Lucide's file outlines leave a margin, so draw marks a bit smaller.
            const size = self.size * mark_scale;
            cx.render(ui.box(.{ .width = self.size, .height = self.size, .alignment = .{ .main = .center, .cross = .center } }, .{
                Svg{ .path = self.kind.icon, .size = size, .viewbox = 16, .color = color },
            }));
        } else {
            cx.render(Svg{ .path = self.kind.icon, .size = self.size, .no_fill = true, .stroke_color = color, .stroke_width = self.size / 12 });
        }
    }
};

const mark_scale: f32 = 0.93;
