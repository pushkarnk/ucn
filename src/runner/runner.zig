const std = @import("std");
const imager = @import("imager");
const util = @import("util");
const watcher = @import("./file_watcher.zig");

const UcnConfig = util.UcnConfig;
const Arena = std.heap.ArenaAllocator;

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
        try runInContainerImpl(&arena, path, rock, config);
    } else {
        std.debug.print("No .rock file found in {s}, skipping container run\n", .{path});
    }
}

fn relaunch(arena: *Arena, name: []const u8, config: UcnConfig) anyerror!void {
    try dockerExecStop(arena, name, config);
    try dockerExecStart(arena, name, config);
}

fn runInContainerImpl(arena: *Arena, path: []const u8, rock_name: []const u8, config: UcnConfig) !void {
    std.debug.print("Found rock file {s} in {s}, building image and running container\n", .{ rock_name, path });

    const archive_rock = try std.mem.concat(arena.allocator(), u8, &.{ "oci-archive:", rock_name });

    var iter = std.mem.tokenizeScalar(u8, rock_name, '_');
    const name = iter.next().?;
    const version = iter.next().?;

    const docker_image = try std.mem.concat(arena.allocator(), u8, &.{ "docker-daemon:", name, ":", version });
    _ = try util.runShellCommand(arena, &.{ "skopeo", "--insecure-policy", "copy", archive_rock, docker_image }, path);

    _ = try dockerRun(arena, name, version, config);

    _ = try dockerExecStart(arena, name, config);

    try watcher.watch(".", relaunch, arena, name, config);
}

fn dockerRun(arena: *Arena, name: []const u8, version: []const u8, config: UcnConfig) !bool {
    const app_name = config.name;
    const port_forward = config.@"port-forward";
    const port_arg = try std.mem.concat(arena.allocator(), u8, &.{ port_forward, ":", port_forward });
    const docker_image = try std.mem.concat(arena.allocator(), u8, &.{ name, ":", version });

    const cwd = try std.process.getCwdAlloc(arena.allocator());
    const volume_arg = try std.mem.concat(arena.allocator(), u8, &.{ cwd, ":/app" });

    return try util.runShellCommand(arena, &.{ "docker", "run", "-d", "--init", "-v", volume_arg, "-p", port_arg, "--name", app_name, "--network", "host", docker_image }, "/");
}

fn dockerExecStart(arena: *Arena, name: []const u8, config: UcnConfig) !void {
    const start_cmd = config.@"start-command";
    if (start_cmd.len == 0) {
        std.debug.print("No start command specified in config, skipping docker exec\n", .{});
        return;
    }

    _ = try util.runShellCommand(arena, &.{ "docker", "exec", "-d", "-w", "/app", name, "sh", "-c", start_cmd }, "/");
}

fn dockerExecStop(arena: *Arena, name: []const u8, config: UcnConfig) !void {
    const stop_cmd = config.@"stop-command";
    if (stop_cmd.len == 0) {
        std.debug.print("No stop command specified in config, skipping docker exec\n", .{});
        return;
    }

    _ = try util.runShellCommand(arena, &.{ "docker", "exec", name, "sh", "-c", stop_cmd }, "/");
}
