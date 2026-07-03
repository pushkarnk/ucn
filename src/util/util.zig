const std = @import("std");
const Yaml = @import("yaml").Yaml;
const Arena = std.heap.ArenaAllocator;
const log = std.log;

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
    @"runtime-deps": []const []const u8,
    @"port-forward": ?[]const u8 = null,
    @"setup-command": ?[]const u8 = null,
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
            log.err("Command exited with code {d}", .{code});
            log.err("{s}", .{stderr.items});
            return error.CommandFailed;
        },
        else => return error.CommandFailed,
    }
    return;
}
