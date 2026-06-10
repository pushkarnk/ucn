const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const yaml_dep = b.dependency("yaml", .{
        .target = target,
        .optimize = optimize,
    });

    const serde_dep = b.dependency("serde", .{
        .target = target,
        .optimize = optimize,
    });

    const util_mod = b.addModule("util", .{
        .root_source_file = b.path("src/util/util.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "yaml", .module = yaml_dep.module("yaml") },
        },
    });

    const imager_mod = b.addModule("imager", .{
        .root_source_file = b.path("src/imager/imager.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "util", .module = util_mod },
            .{ .name = "serde", .module = serde_dep.module("serde") },
        },
    });

    const runner_mod = b.addModule("runner", .{
        .root_source_file = b.path("src/runner/runner.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "util", .module = util_mod },
            .{ .name = "imager", .module = imager_mod },
        },
    });

    const ucn_mod = b.addModule("ucn", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "imager", .module = imager_mod },
            .{ .name = "runner", .module = runner_mod },
            .{ .name = "util", .module = util_mod },
        },
    });

    const lib = b.addLibrary(.{
        .name = "ucn",
        .root_module = ucn_mod,
        .linkage = .static,
    });
    b.installArtifact(lib);

    const exe = b.addExecutable(.{
        .name = "ucn",
        .root_module = ucn_mod,
    });
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);

    const run_step = b.step("run", "Run the ucn binary");
    run_step.dependOn(&run_cmd.step);

    const test_step = b.step("test", "Run all tests");

    for ([_]*std.Build.Module{ imager_mod, runner_mod, ucn_mod }) |mod| {
        const mod_tests = b.addTest(.{ .root_module = mod });
        const run_mod_tests = b.addRunArtifact(mod_tests);
        test_step.dependOn(&run_mod_tests.step);
    }
}
