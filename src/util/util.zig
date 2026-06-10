const std = @import("std");
const Yaml = @import("yaml").Yaml;
const Arena = std.heap.ArenaAllocator;

pub const UcnConfig = struct {
    name: []const u8,
    runtime: []const u8,
    version: []const u8,
    @"ubuntu-version": []const u8,
    @"runtime-version": []const u8,
    description: []const u8,
    @"port-forward": []const u8,
    @"start-command": []const u8,
    @"stop-command": []const u8,
};

pub fn parseConfig(allocator: std.mem.Allocator) !UcnConfig {
    const conf_file = try std.fs.cwd().openFile("ucn.conf", .{});
    defer conf_file.close();

    const conf_data = try conf_file.readToEndAlloc(allocator, 8192);

    var conf_yaml: Yaml = .{ .source = conf_data };
    try conf_yaml.load(allocator);

    return conf_yaml.parse(allocator, UcnConfig);
}

pub fn runShellCommand(arena: *Arena, cmd: []const []const u8, sub_path: []const u8) !bool {
    var child = std.process.Child.init(cmd, arena.allocator());
    // print the command being run for better debugging
    std.debug.print("Running command: {s}\n", .{try std.mem.join(arena.allocator(), " ", cmd)});
    child.cwd = sub_path;
    child.stdout_behavior = .Inherit;
    child.stderr_behavior = .Inherit;
    try child.spawn();
    const term = try child.wait();
    switch (term) {
        .Exited => |code| if (code != 0) {
            std.debug.print("rc = {}\n", .{code});
            return false;
        },
        else => return false,
    }
    return true;
}
