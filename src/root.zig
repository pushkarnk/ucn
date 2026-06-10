const std = @import("std");
const imager = @import("imager");
const runner = @import("runner");
const util = @import("util");
const Arena = std.heap.ArenaAllocator;

pub const std_options: std.Options = .{
    .log_scope_levels = &.{
        .{ .scope = .tokenizer, .level = .warn },
        .{ .scope = .parser, .level = .warn },
    },
};

pub fn main() !void {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    const config = try util.parseConfig(arena.allocator());

    _ = try imager.createImage(".", config);
    _ = try runner.run(".", config);
}
