const std = @import("std");
const Yaml = @import("yaml").Yaml;
const Arena = std.heap.ArenaAllocator;
const log = std.log;

const Command = enum { setup, start, test_cmd, stop };

pub const WatchConfig = struct {
    paths: []const []const u8 = &.{"."},
    ignore: []const []const u8 = &.{},
};

pub const EnvVar = struct {
    name: []const u8,
    value: []const u8,
};

pub const UcnConfig = struct {
    name: []const u8,
    version: []const u8,
    description: []const u8,
    @"ubuntu-version": []const u8,
    toolchain: ?[]const u8 = null,
    @"toolchain-version": ?[]const u8 = null,
    @"build-deps": ?[]const []const u8 = null,
    @"runtime-deps": []const []const u8,
    @"port-forward": ?[]const u8 = null,
    @"setup-command": ?[]const u8 = null,
    @"test-command": ?[]const u8 = null,
    @"start-command": []const u8,
    @"stop-command": []const u8,
    @"readiness-probe": ?[]const u8 = null,
    @"readiness-timeout": ?u64 = null,
    watch: ?WatchConfig = null,
    environment: []const EnvVar = &.{},
};

pub fn parseConfig(allocator: std.mem.Allocator) !UcnConfig {
    const conf_file = try std.fs.cwd().openFile("ucn.yaml", .{});
    defer conf_file.close();

    const conf_data = try conf_file.readToEndAlloc(allocator, 8192);

    var conf_yaml: Yaml = .{ .source = conf_data };
    try conf_yaml.load(allocator);

    // The YAML library's struct parser can't map an arbitrary-keyed mapping
    // onto a Zig type, so pull `environment` out of the document (removing it so
    // the struct parser falls back to the default) and build the list ourselves.
    const environment = extractEnvironment(allocator, &conf_yaml) catch &.{};

    var config = try conf_yaml.parse(allocator, UcnConfig);
    config.environment = environment;
    return config;
}

fn extractEnvironment(allocator: std.mem.Allocator, yaml: *Yaml) ![]const EnvVar {
    if (yaml.docs.items.len == 0) return &.{};
    const root = &yaml.docs.items[0];
    if (root.* != .map) return &.{};

    const entry = root.map.fetchSwapRemove("environment") orelse return &.{};
    const env_map = switch (entry.value) {
        .map => |m| m,
        else => return &.{},
    };

    const vars = try allocator.alloc(EnvVar, env_map.count());
    for (env_map.keys(), env_map.values(), 0..) |key, value, i| {
        vars[i] = .{ .name = key, .value = value.asScalar() orelse "" };
    }
    return vars;
}

pub fn runShellCommand(arena: *Arena, cmd: []const []const u8, expected_rc: u8) !void {
    var child = std.process.Child.init(cmd, arena.allocator());
    log.debug("Running command: {s}", .{try std.mem.join(arena.allocator(), " ", cmd)});

    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;
    try child.spawn();

    var stdout: std.ArrayListUnmanaged(u8) = .empty;
    var stderr: std.ArrayListUnmanaged(u8) = .empty;

    try child.collectOutput(arena.allocator(), &stdout, &stderr, 1 << 20);

    const term = try child.wait();
    switch (term) {
        .Exited => |code| if (code != expected_rc) {
            log.debug("Command exited with code {d}", .{code});
            log.debug("{s}", .{stderr.items});
            return error.CommandFailed;
        },
        else => return error.CommandFailed,
    }
    return;
}

pub fn dockerImageExists(arena: *Arena, name: []const u8, tag: []const u8) bool {
    const image = std.mem.concat(arena.allocator(), u8, &.{ name, ":", tag }) catch return false;
    runShellCommand(arena, &.{ "docker", "image", "inspect", image }, 0) catch return false;
    return true;
}

pub fn dockerContainerExists(arena: *Arena, name: []const u8) bool {
    runShellCommand(arena, &.{ "docker", "container", "inspect", name }, 0) catch return false;
    return true;
}

pub fn checkForRock(allocator: std.mem.Allocator, path: []const u8) !?[]const u8 {
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

pub fn dockerRun(arena: *Arena, container_name: []const u8, name: []const u8, version: []const u8, config: UcnConfig) !void {
    const allocator = arena.allocator();
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

    try args.appendSlice(allocator, &.{ "--name", container_name, "--network", "host", docker_image });
    try runShellCommand(arena, args.items, 0);
}

pub fn dockerExec(arena: *Arena, name: []const u8, config: UcnConfig, cmd: Command, expected_rc: u8) !void {
    const command = switch (cmd) {
        .setup => config.@"setup-command",
        .start => config.@"start-command",
        .stop => config.@"stop-command",
        .test_cmd => config.@"test-command",
    } orelse "";

    if (command.len == 0) {
        if (cmd != .setup) {
            log.err("No {s} command specified in config, aborting.", .{@tagName(cmd)});
        }
        return;
    }

    log.info("Executing {s} command in container: {s}", .{ @tagName(cmd), command });

    if (cmd == .test_cmd) {
        // Chiseled test containers have no shell, so docker exec can't run the
        // command via `sh -c`; split it into argv tokens instead.
        var args: std.ArrayListUnmanaged([]const u8) = .empty;
        try args.appendSlice(arena.allocator(), &.{ "docker", "exec", "-u", "0", "-w", "/app", name });
        var it = std.mem.tokenizeAny(u8, command, " \t");
        while (it.next()) |part| try args.append(arena.allocator(), part);
        _ = try runShellCommand(arena, args.items, expected_rc);
        return;
    }

    // Only the long-running start command is detached. setup (and stop) run in
    // the foreground so docker exec blocks until they complete, guaranteeing
    // setup-command finishes before start-command begins.
    if (cmd == .start) {
        _ = try runShellCommand(arena, &.{ "docker", "exec", "-d", "-w", "/app", name, "sh", "-c", command }, expected_rc);
    } else {
        _ = try runShellCommand(arena, &.{ "docker", "exec", "-w", "/app", name, "sh", "-c", command }, expected_rc);
    }
}
