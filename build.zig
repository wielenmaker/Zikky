const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const gooey = b.dependency("gooey", .{ .target = target, .optimize = optimize });
    const assets = b.createModule(.{ .root_source_file = b.path("assets/assets.zig") });
    // Ghostty's terminal core (libghostty-vt), for the terminal panel.
    const ghostty = b.dependency("ghostty", .{ .target = target, .optimize = optimize });

    const exe = b.addExecutable(.{
        .name = "slate",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "gooey", .module = gooey.module("gooey") },
                .{ .name = "gooey-components", .module = gooey.module("gooey-components") },
                .{ .name = "assets", .module = assets },
                .{ .name = "ghostty-vt", .module = ghostty.module("ghostty-vt") },
            },
        }),
    });
    b.installArtifact(exe);

    const run = b.addRunArtifact(exe);
    b.step("run", "Run Slate").dependOn(&run.step);

    const tests = b.addRunArtifact(b.addTest(.{ .root_module = exe.root_module }));
    b.step("test", "Run Slate's tests").dependOn(&tests.step);
}
