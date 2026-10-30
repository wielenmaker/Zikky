//! Shared looks are written as a base value; each use overrides only the
//! fields it changes: `with(base, .{ .width = 300 })`.

pub fn with(base: anytype, over: anytype) @TypeOf(base) {
    var out = base;
    inline for (@typeInfo(@TypeOf(over)).@"struct".field_names) |name| @field(out, name) = @field(over, name);
    return out;
}
