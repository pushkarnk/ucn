const std = @import("std");
const imager = @import("imager");
const runner = @import("runner");
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
    try imager.createImage(".", config);
    try runner.run(".", config);
}
