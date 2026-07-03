const std = @import("std");
const serde = @import("serde");
const util = @import("util");
const Arena = std.heap.ArenaAllocator;
const UcnConfig = util.UcnConfig;
const log = std.log;
const SkipMode = serde.SkipMode;

const EnvMap = std.StringArrayHashMapUnmanaged([]const u8);

const Rockcraft = struct {
    name: []const u8,
    base: []const u8,
    version: []const u8,
    summary: []const u8,
    description: []const u8,
    environment: ?EnvMap,
    platforms: Platform,
    parts: Parts,

    pub const serde = .{
        .skip = .{
            .environment = SkipMode.null,
        },
    };
};

const Part = struct {
    plugin: ?[]const u8,
    @"stage-packages": ?[]const []const u8,
    @"stage-snaps": ?[]const []const u8,

    pub const serde = .{
        .skip = .{
            .@"stage-snaps" = SkipMode.null,
        },
    };
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
        .environment = try createEnvironment(arena.allocator(), config),
        .platforms = .{ .amd64 = null },
        .parts = try createRuntimePart(arena.allocator(), config),
    };

    return try serde.yaml.toSlice(arena.allocator(), rockcraft);
}

fn createEnvironment(allocator: std.mem.Allocator, config: UcnConfig) !?EnvMap {
    if (config.environment.len == 0) return null;

    var env: EnvMap = .empty;
    for (config.environment) |v| {
        try env.put(allocator, v.name, v.value);
    }
    return env;
}

fn createRuntimePart(allocator: std.mem.Allocator, config: UcnConfig) !Parts {
    // filter apt packages and snaps from the "runtime-deps" list
    // by default every entry is an apt package and must go into "stage-packages"
    // if an entry starts with "snap:", it is a snap package and must go into "stage-snaps"
    var snap_packages: std.ArrayList([]const u8) = .empty;
    var apt_packages: std.ArrayList([]const u8) = .empty;
    for (config.@"runtime-deps") |dep| {
        if (std.mem.startsWith(u8, dep, "snap:")) {
            try snap_packages.append(allocator, dep[5..]);
        } else {
            try apt_packages.append(allocator, dep);
        }
    }
    const part = Part{
        .plugin = "nil",
        .@"stage-packages" = try apt_packages.toOwnedSlice(allocator),
        .@"stage-snaps" = if (snap_packages.items.len == 0) null else try snap_packages.toOwnedSlice(allocator),
    };
    return Parts{ .runtime = part };
}

fn buildImage(arena: *Arena, sub_path: []const u8, rockcraft: []const u8) !void {
    const conf_path = try std.fs.path.join(std.heap.page_allocator, &.{ sub_path, "rockcraft.yaml" });
    try std.fs.cwd().writeFile(.{ .sub_path = conf_path, .data = rockcraft });
    log.info("Creating rock image using the rockcraft.yaml", .{});
    try util.runShellCommand(arena, &.{ "rockcraft", "pack" }, 0);
}

pub fn createImage(path: []const u8, config: UcnConfig) !void {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    log.info("Generating rockcraft.yaml", .{});
    const rockcraft = try createRockcraft(&arena, config);
    try buildImage(&arena, path, rockcraft);
}
