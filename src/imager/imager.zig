const std = @import("std");
const serde = @import("serde");
const util = @import("util");
const rockcraft_directory = @import("rockcraft_directory.zig");

const Arena = std.heap.ArenaAllocator;
const UcnConfig = util.UcnConfig;
const log = std.log;
const SkipMode = serde.SkipMode;

const EnvMap = std.StringArrayHashMapUnmanaged([]const u8);

// Arbitrary-named parts map (runtime, rust, deb-security-manifest, …).
const Parts = std.StringArrayHashMapUnmanaged(Part);

// Multi-line string serialized as a YAML literal block (`|`) so shell
// snippets, regexes, and quotes survive round-trips. Single-line values
// still use plain/quoted scalar style via the serializer.
const YamlBlockString = struct {
    data: []const u8,

    pub fn zerdeSerialize(self: @This(), serializer: anytype) !void {
        if (std.mem.indexOfScalar(u8, self.data, '\n') == null) {
            try serializer.serializeString(self.data);
            return;
        }
        // YAML Serializer exposes out/depth/indent; other formats fall back.
        if (!@hasField(@TypeOf(serializer.*), "out") or !@hasField(@TypeOf(serializer.*), "depth") or !@hasField(@TypeOf(serializer.*), "indent_size")) {
            try serializer.serializeString(self.data);
            return;
        }
        try writeYamlLiteralBlock(serializer.out, serializer.depth, serializer.indent_size, self.data);
    }

    pub fn zerdeDeserialize(comptime _: type, allocator: std.mem.Allocator, deserializer: anytype) @TypeOf(deserializer.*).Error!@This() {
        return .{ .data = try deserializer.deserializeString(allocator) };
    }
};

fn writeYamlLiteralBlock(out: anytype, depth: u32, indent_size: u8, value: []const u8) !void {
    out.writeAll("|\n") catch return error.WriteFailed;
    var start: usize = 0;
    while (start < value.len) {
        const nl = std.mem.indexOfScalarPos(u8, value, start, '\n');
        const end = nl orelse value.len;
        const line = value[start..end];
        const total = depth * indent_size;
        for (0..total) |_| {
            out.writeByte(' ') catch return error.WriteFailed;
        }
        out.writeAll(line) catch return error.WriteFailed;
        if (nl) |n| {
            out.writeByte('\n') catch return error.WriteFailed;
            start = n + 1;
        } else {
            break;
        }
    }
}

const Rockcraft = struct {
    name: []const u8,
    title: ?[]const u8 = null,
    base: []const u8,
    @"build-base": ?[]const u8 = null,
    version: ?[]const u8 = null,
    summary: []const u8,
    license: ?[]const u8 = null,
    description: YamlBlockString,
    @"adopt-info": ?[]const u8 = null,
    environment: ?EnvMap,
    platforms: Platform,
    parts: Parts,
    @"run-user": ?[]const u8 = null,

    pub const serde = .{
        .skip = .{
            .@"build-base" = SkipMode.null,
            .@"run-user" = SkipMode.null,
            .@"adopt-info" = SkipMode.null,
            .license = SkipMode.null,
            .title = SkipMode.null,
            .version = SkipMode.null,
            .environment = SkipMode.null,
        },
    };
};

const Part = struct {
    plugin: ?[]const u8 = null,
    @"stage-packages": ?[]const []const u8 = null,
    @"stage-snaps": ?[]const []const u8 = null,
    @"build-packages": ?[]const []const u8 = null,
    after: ?[]const []const u8 = null,
    source: ?[]const u8 = null,
    @"source-type": ?[]const u8 = null,
    @"source-branch": ?[]const u8 = null,
    @"override-build": ?YamlBlockString = null,
    @"override-prime": ?YamlBlockString = null,

    pub const serde = .{
        .skip = .{
            .plugin = SkipMode.null,
            .@"stage-packages" = SkipMode.null,
            .@"stage-snaps" = SkipMode.null,
            .@"build-packages" = SkipMode.null,
            .after = SkipMode.null,
            .source = SkipMode.null,
            .@"source-type" = SkipMode.null,
            .@"source-branch" = SkipMode.null,
            .@"override-build" = SkipMode.null,
            .@"override-prime" = SkipMode.null,
        },
    };
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
        .description = .{ .data = config.description },
        .environment = try createEnvironment(arena.allocator(), config),
        .platforms = .{ .amd64 = null },
        .parts = try createRuntimePart(arena.allocator(), config),
    };

    return try serde.yaml.toSlice(arena.allocator(), rockcraft);
}

fn createTestRockcraft(arena: *Arena, config: UcnConfig) ![]const u8 {
    const url = rockcraft_directory.getRockcraftUrl(
        config.toolchain.?, //fail if toolchain is null, since we can't create a test rockcraft without it
        config.@"toolchain-version".?, //fail if toolchain-version is null, since we can't create a test rockcraft without it
        config.@"ubuntu-version",
    ) orelse return error.InvalidArguments;

    var client: std.http.Client = .{ .allocator = arena.allocator() };
    defer client.deinit();

    var body: std.Io.Writer.Allocating = .init(arena.allocator());
    defer body.deinit();

    const result = try client.fetch(.{
        .location = .{ .url = url },
        .response_writer = &body.writer,
    });
    if (result.status != .ok) return error.HttpRequestFailed;

    const yaml = try body.toOwnedSlice();
    var rockcraft = try serde.yaml.fromSlice(Rockcraft, arena.allocator(), yaml);

    // TODO: why does this change fail rockcraft pack?
    //rockcraft.name = try std.fmt.allocPrint(arena.allocator(), "{s}-{s}-test", .{ config.name, rockcraft.name });
    //rockcraft.version = config.version;

    const chown_target: ?[]const u8 = if (rockcraft.@"run-user") |user|
        if (std.mem.eql(u8, user, "_daemon_")) "584792" else user
    else
        null;

    const base_script =
        \\rm -f "$CRAFT_PART_INSTALL"/*.rock "$CRAFT_PART_INSTALL"/*.yaml
        \\mkdir -p "$CRAFT_PART_INSTALL/app-orig"
        \\for _f in "$CRAFT_PART_INSTALL"/*; do
        \\  [ -e "$_f" ] || continue
        \\  _b="$(basename "$_f")"
        \\  [ "$_b" = "deps" ] && continue
        \\  [ "$_b" = "app-orig" ] && continue
        \\  mv "$_f" "$CRAFT_PART_INSTALL/app-orig/"
        \\done
    ;
    const organize_script = if (chown_target) |u|
        try std.fmt.allocPrint(arena.allocator(), "{s}\nchown -R {s}:{s} \"$CRAFT_PART_INSTALL/app-orig\"", .{ base_script, u, u })
    else
        base_script;

    const override_build: ?YamlBlockString = if (config.@"test-command") |cmd|
        .{ .data = try std.mem.concat(arena.allocator(), u8, &.{ cmd, "\ncraftctl default\n", organize_script }) }
    else
        .{ .data = try std.mem.concat(arena.allocator(), u8, &.{ "craftctl default\n", organize_script }) };

    const build_packages: ?[]const []const u8 = config.@"build-deps";

    try rockcraft.parts.put(arena.allocator(), "app", .{
        .plugin = "dump",
        .source = ".",
        .@"build-packages" = build_packages,
        .@"override-build" = override_build,
    });

    if (config.environment.len > 0) {
        if (rockcraft.environment == null) {
            rockcraft.environment = .empty;
        }
        for (config.environment) |v| {
            try rockcraft.environment.?.put(arena.allocator(), v.name, v.value);
        }
    }

    const rockcraft_yaml = try serde.yaml.toSlice(arena.allocator(), rockcraft);
    return rockcraft_yaml;
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
    var parts: Parts = .empty;
    try parts.put(allocator, "runtime", part);
    return parts;
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

pub fn createTestImage(path: []const u8, config: UcnConfig) !void {
    var arena = Arena.init(std.heap.page_allocator);
    defer arena.deinit();
    log.info("Generating rockcraft.yaml for test image", .{});
    const rockcraft = try createTestRockcraft(&arena, config);
    try buildImage(&arena, path, rockcraft);

    const rock_file = try util.checkForRock(arena.allocator(), path);
    if (rock_file) |rock| {
        const archive_rock = try std.mem.concat(arena.allocator(), u8, &.{ "oci-archive:", rock });
        const docker_image = try std.mem.concat(arena.allocator(), u8, &.{ "docker-daemon:", config.name, "-test", ":", config.version });
        try util.runShellCommand(&arena, &.{ "skopeo", "--insecure-policy", "copy", archive_rock, docker_image }, 0);
    } else {
        std.debug.print("No .rock file found in {s}, skipping container run\n", .{path});
    }
}
