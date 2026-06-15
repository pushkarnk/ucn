const std = @import("std");
const serde = @import("serde");
const util = @import("util");
const Arena = std.heap.ArenaAllocator;
const UcnConfig = util.UcnConfig;
const log = std.log;

const Rockcraft = struct {
    name: []const u8,
    base: []const u8,
    version: []const u8,
    summary: []const u8,
    description: []const u8,
    platforms: Platform,
    parts: Parts,
};

const Part = struct {
    plugin: ?[]const u8,
    @"stage-packages": ?[]const []const u8,
};

const Parts = struct {
    runtime: Part,
};

const Platform = struct {
    amd64: ?[]const u8,
};

fn createRockcraft(arena: *Arena, config: UcnConfig) ![]const u8 {
    const base = try std.mem.concat(arena.allocator(), u8, &.{ "ubuntu@", config.@"ubuntu-version" });

    const rockcraft = Rockcraft{
        .name = config.name,
        .version = config.version,
        .base = base,
        .summary = config.description,
        .description = config.description,
        .platforms = .{ .amd64 = null },
        .parts = try createRuntimePart(config),
    };

    return try serde.yaml.toSlice(arena.allocator(), rockcraft);
}

fn createRuntimePart(config: UcnConfig) !Parts {
    const part = Part{
        .plugin = "nil",
        .@"stage-packages" = config.@"runtime-deps",
    };
    return Parts{ .runtime = part };
}

fn buildImage(arena: *Arena, sub_path: []const u8, rockcraft: []const u8) !bool {
    const conf_path = try std.fs.path.join(std.heap.page_allocator, &.{ sub_path, "rockcraft.yaml" });
    try std.fs.cwd().writeFile(.{ .sub_path = conf_path, .data = rockcraft });
    log.info("Creating rock image using the rockcraft.yaml", .{});
    return util.runShellCommand(arena, &.{ "rockcraft", "pack" });
}

pub fn createImage(path: []const u8, config: UcnConfig) !bool {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    log.info("Generating rockcraft.yaml", .{});
    const rockcraft = try createRockcraft(&arena, config);
    return try buildImage(&arena, path, rockcraft);
}
