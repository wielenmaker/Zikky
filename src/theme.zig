//! Colors and sizes, taken from Onyx's light and dark themes and layout.
//! `color` is the palette in use; `appearance.zig` switches it.

const gooey = @import("gooey");
const Color = gooey.Color;

pub const Palette = struct {
    dark: bool,
    sidebar_bg: Color,
    sidebar_fg: Color,
    sidebar_accent: Color,
    sidebar_border: Color,
    background: Color,
    foreground: Color,
    muted: Color,
    border: Color,
    primary: Color,
    /// The tab pill: a shade off the window background, like Rex.
    tab_bg: Color,
    tab_fg: Color,
    tab_ring: Color,
    current_line: Color,
    scrollbar: Color,
    /// Under quick open.
    dim: Color,
    /// Floating cards (quick open, the find bar).
    card_shadow: Color,
    syntax: Syntax,
    settings: Settings,
    /// The terminal's 16 ANSI colors (black, red, green, yellow, blue,
    /// magenta, cyan, white, then their bright forms), readable on `background`.
    ansi: [16]Color,
};

/// Syntax colors, muted to sit on the container like the file icons.
pub const Syntax = struct {
    comment: Color,
    string: Color,
    number: Color,
    keyword: Color,
    type: Color,
    call: Color,
    /// YAML / JSON / TOML keys, CSS properties.
    key: Color,
    tag: Color,
    attr: Color,
    heading: Color,
    link: Color,
    code: Color,
    emphasis: Color,
    /// List and quote markers, code fences, rules.
    punct: Color,
    variable: Color,
    added: Color,
    removed: Color,
};

/// The settings window, matching Rex's.
pub const Settings = struct {
    sidebar_bg: Color,
    selected: Color,
    search_bg: Color,
    content_bg: Color,
    group_bg: Color,
    divider: Color,
    control_bg: Color,
    toggle_off: Color,
    accent: Color,
    title: Color,
    label: Color,
    input_bg: Color,
    input_border: Color,
};

pub const light = Palette{
    .dark = false,
    .sidebar_bg = Color.hex(0xf4f3f1),
    .sidebar_fg = Color.hex(0x2b2a30),
    .sidebar_accent = Color.hex(0xe9e7e3),
    .sidebar_border = Color.hex(0xe6e4e0),
    .background = Color.hex(0xffffff),
    .foreground = Color.hex(0x1f1f23),
    .muted = Color.hex(0x76757f),
    .border = Color.hex(0xe7e6ea),
    .primary = Color.hex(0x6d5df2),
    .tab_bg = Color.hex(0xedecea),
    .tab_fg = Color.hex(0x34393f),
    .tab_ring = Color.hex(0xd2d2d2),
    .current_line = Color.hex(0xf4f3f1).withAlpha(0.6),
    .scrollbar = Color.rgba(0, 0, 0, 0.2),
    .dim = Color.rgba(0, 0, 0, 0.25),
    .card_shadow = Color.rgba(0, 0, 0, 0.18),
    .syntax = .{
        .comment = Color.hex(0x9a99a3),
        .string = Color.hex(0x4e8a3e),
        .number = Color.hex(0xb5652a),
        .keyword = Color.hex(0x9b4dab),
        .type = Color.hex(0xa57a17),
        .call = Color.hex(0x3c6fc4),
        .key = Color.hex(0x2b7a87),
        .tag = Color.hex(0xc0492f),
        .attr = Color.hex(0xa57a17),
        .heading = Color.hex(0x2f5fb3),
        .link = Color.hex(0x3c6fc4),
        .code = Color.hex(0x4e8a3e),
        .emphasis = Color.hex(0x9b4dab),
        .punct = Color.hex(0xb5652a),
        .variable = Color.hex(0xc0492f),
        .added = Color.hex(0x4e8a3e),
        .removed = Color.hex(0xc0392b),
    },
    .settings = .{
        .sidebar_bg = Color.hex(0xfafafa),
        .selected = Color.hex(0xf0f0f0),
        .search_bg = Color.hex(0xeaebeb),
        .content_bg = Color.hex(0xf4f4f4),
        .group_bg = Color.hex(0xededed),
        .divider = Color.hex(0xe0e0e1),
        .control_bg = Color.hex(0xdbdbdb),
        .toggle_off = Color.hex(0xd4d4d4),
        .accent = Color.hex(0x3d6aa6),
        .title = Color.hex(0x252525),
        .label = Color.hex(0x34393f),
        .input_bg = Color.hex(0xfbfcfe),
        .input_border = Color.hex(0xd3d4d6),
    },
    .ansi = hexes(.{
        0x1f1f23, 0xc0392b, 0x3f8a36, 0x9c7414, 0x3c6fc4, 0x9b4dab, 0x2b7a87, 0x8a8994,
        0x76757f, 0xd9503f, 0x4e9a3e, 0xb5871c, 0x4b80d6, 0xb15fc4, 0x3a95a3, 0x52515a,
    }),
};

/// Onyx Dark.
pub const dark = Palette{
    .dark = true,
    .sidebar_bg = Color.hex(0x141416),
    .sidebar_fg = Color.hex(0xd9d8de),
    .sidebar_accent = Color.hex(0x222126),
    .sidebar_border = Color.hex(0x232227),
    .background = Color.hex(0x1c1c1f),
    .foreground = Color.hex(0xe8e7ec),
    .muted = Color.hex(0x8d8b97),
    .border = Color.hex(0x2d2c32),
    .primary = Color.hex(0x8577ff),
    .tab_bg = Color.hex(0x222126),
    .tab_fg = Color.hex(0xe8e7ec),
    .tab_ring = Color.hex(0x37363e),
    .current_line = Color.hex(0x26252b).withAlpha(0.7),
    .scrollbar = Color.rgba(1, 1, 1, 0.15),
    .dim = Color.rgba(0, 0, 0, 0.45),
    .card_shadow = Color.rgba(0, 0, 0, 0.5),
    .syntax = .{
        .comment = Color.hex(0x8d8b97),
        .string = Color.hex(0xa3e09f),
        .number = Color.hex(0xcc9e00),
        .keyword = Color.hex(0x87b1f6),
        .type = Color.hex(0xcba6f7),
        .call = Color.hex(0xb3c5f3),
        .key = Color.hex(0x8ccfd8),
        .tag = Color.hex(0xf28b82),
        .attr = Color.hex(0x7faef9),
        .heading = Color.hex(0xcc9e00),
        .link = Color.hex(0x419cff),
        .code = Color.hex(0xa3e09f),
        .emphasis = Color.hex(0xcba6f7),
        .punct = Color.hex(0xe5a46a),
        .variable = Color.hex(0xf28b82),
        .added = Color.hex(0x8ccf7e),
        .removed = Color.hex(0xf28b82),
    },
    .settings = .{
        .sidebar_bg = Color.hex(0x1e1e20),
        .selected = Color.hex(0x2c2c2f),
        .search_bg = Color.hex(0x2a2a2d),
        .content_bg = Color.hex(0x18181a),
        .group_bg = Color.hex(0x222225),
        .divider = Color.hex(0x2e2e31),
        .control_bg = Color.hex(0x333336),
        .toggle_off = Color.hex(0x3a3a3e),
        .accent = Color.hex(0x4f7fc0),
        .title = Color.hex(0xececee),
        .label = Color.hex(0xd6d6d9),
        .input_bg = Color.hex(0x1c1c1f),
        .input_border = Color.hex(0x3a3a3e),
    },
    .ansi = hexes(.{
        0x2a2930, 0xf28b82, 0xa3e09f, 0xcc9e00, 0x87b1f6, 0xcba6f7, 0x8ccfd8, 0xd9d8de,
        0x6b6a75, 0xff9e96, 0xb8f0b4, 0xe8b829, 0xa6c6fa, 0xdcc1fa, 0xa8e2e9, 0xffffff,
    }),
};

fn hexes(comptime values: [16]u32) [16]Color {
    var out: [16]Color = undefined;
    for (values, 0..) |v, i| out[i] = Color.hex(v);
    return out;
}

/// The palette in use.
pub var color: *const Palette = &light;

/// Tailwind's shadow-xs, as GPUI draws it.
pub const shadow_xs = gooey.ui.ShadowConfig{ .blur_radius = 2, .offset_y = 1, .color = Color.rgba(0, 0, 0, 0.05) };

pub const ui_font_size: f32 = 14;
pub const mono_font_size: f32 = 13;

pub const sidebar_width: f32 = 260;
pub const titlebar_height: f32 = 44;
pub const traffic_lights = .{ .x = 16, .y = 15 };
pub const inset: f32 = 8;
pub const radius: f32 = 8;
pub const radius_lg: f32 = 12;
pub const row_height: f32 = 28;
/// From the editor container's top edge to its first line.
pub const editor_top: f32 = 10;
pub const indent: f32 = 16;

/// Settings window sizes.
pub const settings = struct {
    pub const sidebar_width: f32 = 215;
    pub const text_size: u16 = 13;
};
