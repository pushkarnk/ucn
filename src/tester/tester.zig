const std = @import("std");
const log = std.log;
const util = @import("util");
const Arena = std.heap.ArenaAllocator;

pub fn runTests(config: util.UcnConfig) !void {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    const container_name = try std.mem.concat(arena.allocator(), u8, &.{ config.name, "-", config.version, "-test" });
    const image_name = try std.mem.concat(arena.allocator(), u8, &.{ config.name, "-test" });
    if (!util.dockerContainerExists(&arena, container_name)) {
        try util.dockerRun(&arena, container_name, image_name, config.version, config);
    }
    try util.dockerExec(&arena, container_name, config, .test_cmd, 0);
}
