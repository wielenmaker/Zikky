const std = @import("std");

/// The oldest macOS Zikky runs on: Zig 0.17's floor. Keep scripts/bundle.sh's
/// LSMinimumSystemVersion in step.
const macos_min: std.SemanticVersion = .{ .major = 15, .minor = 0, .patch = 0 };

pub fn build(b: *std.Build) void {
    // Default to this Mac but with `macos_min` as the minimum, instead of the
    // version this Mac happens to run.
    const target = b.standardTargetOptions(.{ .default_target = .{ .os_version_min = .{ .semver = macos_min } } });
    const optimize = b.standardOptimizeOption(.{});
    const gooey = b.dependency("gooey", .{ .target = target, .optimize = optimize });
    const assets = b.createModule(.{ .root_source_file = b.path("assets/assets.zig") });
    // Ghostty's terminal core (libghostty-vt), for the terminal panel.
    const ghostty = b.dependency("ghostty", .{ .target = target, .optimize = optimize });

    const exe = b.addExecutable(.{
        .name = "zikky",
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
    // Zig only finds the macOS SDK on its own for the exact native target.
    if (target.result.os.tag == .macos and !target.query.isNative()) {
        if (std.zig.system.darwin.getSdk(b.allocator, b.graph.io, &target.result)) |sdk| {
            exe.root_module.addSystemFrameworkPath(.{ .cwd_relative = b.pathJoin(&.{ sdk, "System/Library/Frameworks" }) });
            exe.root_module.addLibraryPath(.{ .cwd_relative = b.pathJoin(&.{ sdk, "usr/lib" }) });
        }
    }
    b.installArtifact(exe);

    const run = b.addRunArtifact(exe);
    b.step("run", "Run Zikky").dependOn(&run.step);

    const tests = b.addRunArtifact(b.addTest(.{ .root_module = exe.root_module }));
    b.step("test", "Run Zikky's tests").dependOn(&tests.step);
}
