const std = @import("std");
const imager = @import("imager");
const util = @import("util");
const Command = util.Command;
const watcher = @import("./file_watcher.zig");

const UcnConfig = util.UcnConfig;
const Arena = std.heap.ArenaAllocator;
const log = std.log;

pub fn run(path: []const u8, config: UcnConfig) !void {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();

    const rock_file = try util.checkForRock(arena.allocator(), path);
    if (rock_file) |rock| {
        try runInContainerImpl(&arena, rock, config);
    } else {
        std.debug.print("No .rock file found in {s}, skipping container run\n", .{path});
    }
}

fn relaunch(arena: *Arena, name: []const u8, config: UcnConfig) anyerror!void {
    try util.dockerExec(arena, name, config, .stop, 130);
    try util.dockerExec(arena, name, config, .start, 0);
    try waitForReady(arena, config);
}

fn runInContainerImpl(arena: *Arena, rock_name: []const u8, config: UcnConfig) !void {
    log.info("Copying {s} to the docker-daemon", .{rock_name});

    const archive_rock = try std.mem.concat(arena.allocator(), u8, &.{ "oci-archive:", rock_name });

    var iter = std.mem.tokenizeScalar(u8, rock_name, '_');
    const name = iter.next().?;
    const version = iter.next().?;

    const docker_image = try std.mem.concat(arena.allocator(), u8, &.{ "docker-daemon:", name, ":", version });
    try util.runShellCommand(arena, &.{ "skopeo", "--insecure-policy", "copy", archive_rock, docker_image }, 0);
    try util.dockerRun(arena, name, name, version, config);
    try util.dockerExec(arena, name, config, .setup, 0);
    try util.dockerExec(arena, name, config, .start, 0);
    try waitForReady(arena, config);
    try watcher.watch(relaunch, arena, name, config);
}

fn stop(config: UcnConfig) !void {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();

    const name = config.name;
    log.info("Stopping container {s}", .{name});
    try util.runShellCommand(&arena, &.{ "docker", "stop", name }, 0);
    try util.runShellCommand(&arena, &.{ "docker", "rm", name }, 0);
}

const default_readiness_timeout_s: u64 = 30;

fn probeSucceeds(arena: *Arena, command: []const u8) bool {
    var child = std.process.Child.init(
        &.{ "sh", "-c", command },
        arena.allocator(),
    );
    child.stdout_behavior = .Ignore;
    child.stderr_behavior = .Ignore;
    child.spawn() catch return false;
    const term = child.wait() catch return false;
    return switch (term) {
        .Exited => |code| code == 0,
        else => false,
    };
}

fn waitForReady(arena: *Arena, config: UcnConfig) !void {
    const command = config.@"readiness-probe" orelse return;
    if (command.len == 0) return;

    const timeout_s = config.@"readiness-timeout" orelse default_readiness_timeout_s;
    log.info("Waiting up to {d}s for readiness probe: {s}", .{ timeout_s, command });

    var elapsed: u64 = 0;
    while (elapsed < timeout_s) : (elapsed += 1) {
        if (probeSucceeds(arena, command)) {
            log.info("Application ready after {d}s", .{elapsed});
            return;
        }
        std.Thread.sleep(std.time.ns_per_s);
    }

    log.err("Readiness probe did not succeed within {d}s", .{timeout_s});
    return error.ReadinessProbeTimeout;
}
