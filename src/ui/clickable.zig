//! The base of Zikky's buttons and rows: a box that takes a click and shows its hover fill while the
//! pointer is over it or anything inside it (gooey's `hover_background` only fires over the box
//! itself, so it died over an icon, which is a box of its own).

const gooey = @import("gooey");

const ui = gooey.ui;
const Cx = gooey.Cx;
const Color = gooey.Color;

pub const Look = struct {
    fill: Color = Color.transparent,
    /// Null: no hover fill (disabled, or already highlighted).
    hover: ?Color = null,
    /// Null: the box takes no click (disabled).
    on_click: ?ui.HandlerRef = null,
};

pub fn Element(comptime Children: type) type {
    return struct {
        look: Look,
        props: ui.Box,
        children: Children,

        pub fn render(self: @This(), cx: *Cx) void {
            const id = cx.idFor(null);
            var props = self.props;
            props.background = self.look.fill;
            if (self.look.hover) |hover| {
                if (cx.window().isHoveredOrDescendant(id.id)) props.background = hover;
            }
            props.on_click_handler = self.look.on_click;
            cx.render(ui.box_with_layout_id(id, props, self.children));
        }
    };
}

/// Like `ui.box`; `look` sets the background and the click, so `props` leaves them out.
pub fn box(look: Look, props: ui.Box, children: anytype) Element(@TypeOf(children)) {
    return .{ .look = look, .props = props, .children = children };
}
