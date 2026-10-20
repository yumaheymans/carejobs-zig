const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // The module other packages import with `b.dependency("carejobs", .{}).module("carejobs")`.
    const mod = b.addModule("carejobs", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
    });

    const mod_tests = b.addTest(.{ .root_module = mod });
    const run_mod_tests = b.addRunArtifact(mod_tests);
    const test_step = b.step("test", "Run the offline tests (answers recorded from the live API)");
    test_step.dependOn(&run_mod_tests.step);

    // `zig build live` asks the real API.
    const live = b.addExecutable(.{
        .name = "live",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/live.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "carejobs", .module = mod }},
        }),
    });
    const run_live = b.addRunArtifact(live);
    const live_step = b.step("live", "Run examples/live.zig against the live API");
    live_step.dependOn(&run_live.step);
}
