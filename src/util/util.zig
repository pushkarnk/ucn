const std = @import("std");
const serde = @import("serde");
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

// Arbitrary-keyed `environment` map, deserialized by hand since serde has no
// hash map support.
pub const EnvVars = struct {
    vars: []const EnvVar = &.{},

    pub fn zerdeDeserialize(comptime _: type, allocator: std.mem.Allocator, deserializer: anytype) @TypeOf(deserializer.*).Error!@This() {
        var access = try deserializer.deserializeStruct(void);
        var vars: std.ArrayListUnmanaged(EnvVar) = .empty;
        while (try access.nextKey(allocator)) |key| {
            const value = try access.nextValue([]const u8, allocator);
            try vars.append(allocator, .{ .name = key, .value = value });
        }
        return .{ .vars = vars.items };
    }
};

pub const ReadinessConfig = struct {
    probe: []const u8,
    timeout: ?u64 = null,
};

pub const RunConfig = struct {
    @"setup-command": ?[]const u8 = null,
    @"start-command": []const u8,
    @"stop-command": []const u8,
    @"port-forward": ?[]const u8 = null,
    readiness: ?ReadinessConfig = null,
    watch: ?WatchConfig = null,
};

pub const TestConfig = struct {
    toolchain: ?[]const u8 = null,
    @"toolchain-version": ?[]const u8 = null,
    @"build-deps": ?[]const []const u8 = null,
    @"test-command": ?[]const u8 = null,
};

pub const UcnConfig = struct {
    name: []const u8,
    version: []const u8,
    summary: []const u8,
    @"ubuntu-version": []const u8,
    @"runtime-deps": []const []const u8,
    environment: EnvVars = .{},
    run: RunConfig,
    @"test": ?TestConfig = null,
};

pub fn parseConfig(allocator: std.mem.Allocator) !UcnConfig {
    const conf_file = try std.fs.cwd().openFile("ucn.yaml", .{});
    defer conf_file.close();

    const conf_data = try conf_file.readToEndAlloc(allocator, 8192);

    return parseConfigSlice(allocator, conf_data);
}

fn parseConfigSlice(allocator: std.mem.Allocator, data: []const u8) !UcnConfig {
    return try serde.yaml.fromSlice(UcnConfig, allocator, data);
}

test parseConfigSlice {
    const yaml =
        \\name: demo
        \\version: "0.1"
        \\summary: demo app
        \\ubuntu-version: "24.04"
        \\runtime-deps: [cargo]
        \\environment:
        \\  CARGO_HOME: /deps
        \\run:
        \\  setup-command: |
        \\    apt update
        \\    cargo fetch --locked
        \\  start-command: cargo run
        \\  stop-command: pkill cargo
        \\  port-forward: "8080"
        \\  readiness:
        \\    probe: curl -fsS http://127.0.0.1:8080/
        \\    timeout: 120
        \\test:
        \\  test-command: cargo test
    ;

    var arena = Arena.init(std.testing.allocator);
    defer arena.deinit();
    const config = try parseConfigSlice(arena.allocator(), yaml);

    try std.testing.expectEqualStrings("demo", config.name);
    try std.testing.expectEqualStrings("apt update\ncargo fetch --locked\n", config.run.@"setup-command".?);
    try std.testing.expectEqualStrings("cargo run", config.run.@"start-command");
    try std.testing.expectEqual(@as(u64, 120), config.run.readiness.?.timeout.?);
    try std.testing.expectEqualStrings("/deps", config.environment.vars[0].value);
    try std.testing.expectEqualStrings("cargo test", config.@"test".?.@"test-command".?);
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

    if (config.run.@"port-forward") |port_forward| {
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
        .setup => config.run.@"setup-command",
        .start => config.run.@"start-command",
        .stop => config.run.@"stop-command",
        .test_cmd => if (config.@"test") |t| t.@"test-command" else null,
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
    // `sh -e` keeps multi-line (block scalar) commands fail-fast like `&&` chains.
    if (cmd == .start) {
        _ = try runShellCommand(arena, &.{ "docker", "exec", "-d", "-w", "/app", name, "sh", "-e", "-c", command }, expected_rc);
    } else {
        _ = try runShellCommand(arena, &.{ "docker", "exec", "-w", "/app", name, "sh", "-e", "-c", command }, expected_rc);
    }
}
