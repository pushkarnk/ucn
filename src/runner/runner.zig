const std = @import("std");
const imager = @import("imager");
const util = @import("util");
const watcher = @import("./file_watcher.zig");

const UcnConfig = util.UcnConfig;
const Arena = std.heap.ArenaAllocator;
const log = std.log;

const Command = enum { setup, start, stop };

fn checkForRock(allocator: std.mem.Allocator, path: []const u8) !?[]const u8 {
    var dir = std.fs.cwd().openDir(path, .{ .iterate = true }) catch {
        std.debug.print("Failed to open directory {s}\n", .{path});
        return null;
    };
    defer dir.close();

    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        if (entry.kind == .file and std.mem.endsWith(u8, entry.name, ".rock")) {
            return try allocator.dupe(u8, entry.name);
        }
    }
    return null;
}

pub fn run(path: []const u8, config: UcnConfig) !void {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();

    const rock_file = try checkForRock(arena.allocator(), path);
    if (rock_file) |rock| {
        try runInContainerImpl(&arena, rock, config);
    } else {
        std.debug.print("No .rock file found in {s}, skipping container run\n", .{path});
    }
}

fn relaunch(arena: *Arena, name: []const u8, config: UcnConfig) anyerror!void {
    try dockerExec(arena, name, config, .stop);
    try dockerExec(arena, name, config, .start);
}

fn runInContainerImpl(arena: *Arena, rock_name: []const u8, config: UcnConfig) !void {
    log.info("Copying {s} to the docker-daemon", .{rock_name});

    const archive_rock = try std.mem.concat(arena.allocator(), u8, &.{ "oci-archive:", rock_name });

    var iter = std.mem.tokenizeScalar(u8, rock_name, '_');
    const name = iter.next().?;
    const version = iter.next().?;

    const docker_image = try std.mem.concat(arena.allocator(), u8, &.{ "docker-daemon:", name, ":", version });
    _ = try util.runShellCommand(arena, &.{ "skopeo", "--insecure-policy", "copy", archive_rock, docker_image });
    _ = try dockerRun(arena, name, version, config);
    _ = try dockerExec(arena, name, config, .setup);
    _ = try dockerExec(arena, name, config, .start);
    try watcher.watch(".", relaunch, arena, name, config);
}

fn dockerRun(arena: *Arena, name: []const u8, version: []const u8, config: UcnConfig) !bool {
    const allocator = arena.allocator();
    const app_name = config.name;
    const docker_image = try std.mem.concat(allocator, u8, &.{ name, ":", version });

    const cwd = try std.process.getCwdAlloc(allocator);
    const volume_arg = try std.mem.concat(allocator, u8, &.{ cwd, ":/app" });

    var args: std.ArrayListUnmanaged([]const u8) = .empty;
    try args.appendSlice(allocator, &.{ "docker", "run", "-d", "--init", "-v", volume_arg });

    if (config.@"port-forward") |port_forward| {
        const port_arg = try std.mem.concat(allocator, u8, &.{ port_forward, ":", port_forward });
        try args.appendSlice(allocator, &.{ "-p", port_arg });
        log.info("Starting container {s} with port forwarding for port {s}", .{ docker_image, port_forward });
    } else {
        log.info("Starting container {s} without port forwarding", .{docker_image});
    }

    try args.appendSlice(allocator, &.{ "--name", app_name, "--network", "host", docker_image });
    return try util.runShellCommand(arena, args.items);
}

fn dockerExec(arena: *Arena, name: []const u8, config: UcnConfig, cmd: Command) !void {
    const command = switch (cmd) {
        .setup => config.@"setup-command",
        .start => config.@"start-command",
        .stop => config.@"stop-command",
    } orelse "";

    if (command.len == 0) {
        if (cmd != .setup) {
            log.err("No {s} command specified in config, aborting.", .{@tagName(cmd)});
        }
        return;
    }

    log.info("Executing {s} command in container: {s}", .{ @tagName(cmd), command });
    _ = try util.runShellCommand(arena, &.{ "docker", "exec", "-d", "-w", "/app", name, "sh", "-c", command });
}
