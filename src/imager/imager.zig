const std = @import("std");
const serde = @import("serde");
const util = @import("util");
const Arena = std.heap.ArenaAllocator;
const UcnConfig = util.UcnConfig;

pub fn createImage(path: []const u8, config: UcnConfig) !bool {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    const rockcraft = try createRockcraft(&arena, config);
    return try buildImage(&arena, path, rockcraft);
}

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
    if (std.mem.eql(u8, config.runtime, "dotnet")) {
        return try createDotnetRockcraft(arena, config);
    } else {
        return error.UnsupportedRuntime;
    }
}

fn createDotnetRockcraft(arena: *Arena, config: UcnConfig) ![]const u8 {
    const base = try std.mem.concat(arena.allocator(), u8, &.{ "ubuntu@", config.@"ubuntu-version" });
    defer arena.allocator().free(base);

    const part = Part{
        .plugin = "nil",
        .@"stage-packages" = &.{try dotnetVersion(arena, config)},
    };

    const runtime_part = Parts{ .runtime = part };
    const rockcraft = Rockcraft{
        .name = config.name,
        .version = config.version,
        .base = base,
        .summary = config.description,
        .description = config.description,
        .platforms = .{ .amd64 = null },
        .parts = runtime_part,
    };

    const yaml_bytes = try serde.yaml.toSlice(arena.allocator(), rockcraft);

    return yaml_bytes;
}

// fn createJavaRockcraft(arena: Arena, config: UcnConfig) ![]const u8 {}

// fn createPythonRockcraft(arena: Arena, config: UcnConfig) !Yaml {}

// fn createRustRockcraft(arena: Arena, config: UcnConfig) !Yaml {}

fn dotnetVersion(arena: *Arena, config: UcnConfig) ![]const u8 {
    const package = try std.mem.concat(arena.allocator(), u8, &.{ config.runtime, config.@"runtime-version" });
    return package;
}

fn buildImage(arena: *Arena, sub_path: []const u8, rockcraft: []const u8) !bool {
    const conf_path = try std.fs.path.join(std.heap.page_allocator, &.{ sub_path, "rockcraft.yaml" });
    try std.fs.cwd().writeFile(.{ .sub_path = conf_path, .data = rockcraft });
    return util.runShellCommand(arena, &.{ "rockcraft", "pack" }, sub_path);
}

// test "createImage on dotnet-sample" {
//     const result = try createImage("samples/dotnet-sample");
//     try std.testing.expect(result == true);
// }
