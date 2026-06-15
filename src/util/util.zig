const std = @import("std");
const Yaml = @import("yaml").Yaml;
const Arena = std.heap.ArenaAllocator;
const log = std.log;

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
};

pub fn parseConfig(allocator: std.mem.Allocator) !UcnConfig {
    const conf_file = try std.fs.cwd().openFile("ucn.yaml", .{});
    defer conf_file.close();

    const conf_data = try conf_file.readToEndAlloc(allocator, 8192);

    var conf_yaml: Yaml = .{ .source = conf_data };
    try conf_yaml.load(allocator);

    return conf_yaml.parse(allocator, UcnConfig);
}

pub fn runShellCommand(arena: *Arena, cmd: []const []const u8) !bool {
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
        .Exited => |code| if (code != 0) {
            log.err("Command exited with code {d}", .{code});
            log.err("{s}", .{stderr.items});
            return false;
        },
        else => return false,
    }
    return true;
}
