//! CoreText backend for macOS text rendering
//!
//! Provides font loading, text shaping, and glyph rasterization
//! using Apple's CoreText and CoreGraphics frameworks.

pub const bindings = @import("bindings.zig");
pub const CoreTextFace = @import("face.zig").CoreTextFace;
pub const CoreTextShaper = @import("shaper.zig").CoreTextShaper;

// Re-export common types
pub const CTFontRef = bindings.CTFontRef;
pub const CGGlyph = bindings.CGGlyph;

test {
    @import("std").testing.refAllDecls(@This());
}
