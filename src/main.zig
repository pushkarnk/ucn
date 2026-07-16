const std = @import("std");
const imager = @import("imager");
const runner = @import("runner");
const tester = @import("tester");
const util = @import("util");
const posix = std.posix;
const Arena = std.heap.ArenaAllocator;

pub const std_options: std.Options = .{
    .log_level = .info,
    .logFn = ucnLogFn,
    .log_scope_levels = &.{
        .{ .scope = .tokenizer, .level = .warn },
        .{ .scope = .parser, .level = .warn },
    },
};

fn ucnLogFn(comptime level: std.log.Level, comptime scope: @TypeOf(.enum_literal), comptime format: []const u8, args: anytype) void {
    const color = switch (level) {
        .debug => "\x1b[36m", // Cyan
        .info => "\x1b[32m", // Green
        .warn => "\x1b[33m", // Yellow
        .err => "\x1b[31m", // Red
    };

    var buffer: [1024]u8 = undefined;
    var writer = std.debug.lockStderrWriter(&buffer);
    defer std.debug.unlockStderrWriter();
    writer.print(color ++ "{s}" ++ "\x1b[0m" ++ "({s}): " ++ format ++ "\n", .{
        level.asText(),
        @tagName(scope),
    } ++ args) catch return;
}

pub fn main() !void {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    const config = try util.parseConfig(arena.allocator());
    const argv = std.process.argsAlloc(arena.allocator()) catch return error.OutOfMemory;
    defer std.process.argsFree(arena.allocator(), argv);

    if (argv.len < 2) {
        std.debug.print("Usage: {s} <command> [args...]\n", .{argv[0]});
        return error.InvalidArguments;
    }

    if (std.mem.eql(u8, argv[1], "run")) {
        try imager.createImage(".", config);
        try runner.run(".", config);
    } else if (std.mem.eql(u8, argv[1], "test")) {
        const test_image = try std.mem.concat(arena.allocator(), u8, &.{ config.name, "-test" });
        if (!util.dockerImageExists(&arena, test_image, config.version)) {
            try imager.createTestImage(".", config);
        }
        try tester.runTests(config);
    } else if (std.mem.eql(u8, argv[1], "deploy")) {
        //try imager.createDeployImage(".", config);
        // try deployer.deploy(".", config);
    } else if (std.mem.eql(u8, argv[1], "stop")) {
        //try runner.stop(config);
    } else {
        std.debug.print("Unknown command: {s}\n", .{argv[1]});
        return error.InvalidArguments;
    }
}
