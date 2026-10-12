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

// Both run and test images are the chiseled toolchain rock with an injected
// app part; the test image additionally stages the full runtime-deps toolchain
// and runs the test-command at build time.
fn fetchToolchainRockcraft(arena: *Arena, config: UcnConfig) !Rockcraft {
    const toolchain = config.toolchain orelse return error.InvalidArguments;
    const toolchain_version = config.@"toolchain-version" orelse return error.InvalidArguments;
    const url = rockcraft_directory.getRockcraftUrl(toolchain, toolchain_version, config.@"ubuntu-version") orelse return error.InvalidArguments;

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
    return try serde.yaml.fromSlice(Rockcraft, arena.allocator(), yaml);
}

fn mergeEnvironment(allocator: std.mem.Allocator, rockcraft: *Rockcraft, config: UcnConfig) !void {
    if (config.environment.vars.len == 0) return;
    if (rockcraft.environment == null) rockcraft.environment = .empty;
    for (config.environment.vars) |v| {
        try rockcraft.environment.?.put(allocator, v.name, v.value);
    }
}

// Moves the dumped app files into app-orig (deps cache stays at the root),
// chowned to the rock's run-user if it has one.
fn organizeScript(arena: *Arena, rockcraft: Rockcraft) ![]const u8 {
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

    const chown_target: ?[]const u8 = if (rockcraft.@"run-user") |user|
        if (std.mem.eql(u8, user, "_daemon_")) "584792" else user
    else
        null;

    if (chown_target) |u|
        return try std.fmt.allocPrint(arena.allocator(), "{s}\nchown -R {s}:{s} \"$CRAFT_PART_INSTALL/app-orig\"", .{ base_script, u, u });
    return base_script;
}

// split runtime-deps into apt packages (stage-packages) and snap: entries
// (stage-snaps)
fn splitDeps(allocator: std.mem.Allocator, deps: []const []const u8) !struct { apt: []const []const u8, snaps: ?[]const []const u8 } {
    var snap_packages: std.ArrayList([]const u8) = .empty;
    var apt_packages: std.ArrayList([]const u8) = .empty;
    for (deps) |dep| {
        if (std.mem.startsWith(u8, dep, "snap:")) {
            try snap_packages.append(allocator, dep[5..]);
        } else {
            try apt_packages.append(allocator, dep);
        }
    }
    return .{
        .apt = try apt_packages.toOwnedSlice(allocator),
        .snaps = if (snap_packages.items.len == 0) null else try snap_packages.toOwnedSlice(allocator),
    };
}

// Run image: chiseled toolchain rock + app source. The chiseled rocks have no
// shell, but setup/start/stop commands run via `sh -c`, so stage dash and
// link it to sh.
fn createRockcraft(arena: *Arena, config: UcnConfig) ![]const u8 {
    var rockcraft = try fetchToolchainRockcraft(arena, config);
    try mergeEnvironment(arena.allocator(), &rockcraft, config);

    const override_build: ?YamlBlockString = .{ .data = try std.mem.concat(arena.allocator(), u8, &.{
        "craftctl default\n",
        try organizeScript(arena, rockcraft),
        \\
        \\mkdir -p "$CRAFT_PART_INSTALL/usr/bin"
        \\ln -sf dash "$CRAFT_PART_INSTALL/usr/bin/sh"
    }) };

    const after = try arena.allocator().dupe([]const u8, rockcraft.parts.keys());
    try rockcraft.parts.put(arena.allocator(), "app", .{
        .plugin = "dump",
        .source = ".",
        .after = after,
        .@"stage-packages" = &.{"dash"},
        .@"override-build" = override_build,
    });

    return try serde.yaml.toSlice(arena.allocator(), rockcraft);
}

// Test image: same as the run image, but with the full deb toolchain from
// runtime-deps staged in (the chisel slices ship binaries without their libs,
// rustdoc, etc.), the /deps cache baked at build time, and the test-command
// as a build-time gate.
fn createTestRockcraft(arena: *Arena, config: UcnConfig) ![]const u8 {
    const test_config = config.@"test" orelse return error.InvalidArguments;

    var rockcraft = try fetchToolchainRockcraft(arena, config);
    rockcraft.name = try std.mem.concat(arena.allocator(), u8, &.{ config.name, "-test" });
    rockcraft.version = config.version;
    try mergeEnvironment(arena.allocator(), &rockcraft, config);

    // The full toolchain goes in its own part so the app part's organize
    // script never relocates it into app-orig.
    const deps = try splitDeps(arena.allocator(), config.@"runtime-deps");
    try rockcraft.parts.put(arena.allocator(), "test-runtime", .{
        .plugin = "nil",
        .after = try arena.allocator().dupe([]const u8, rockcraft.parts.keys()),
        .@"stage-packages" = deps.apt,
        .@"stage-snaps" = deps.snaps,
        // debs regenerate files the chiseled parts already stage (e.g.
        // ca-certificates.crt); drop overlaps so staging doesn't conflict
        .@"override-build" = .{ .data =
        \\craftctl default
        \\cd "$CRAFT_PART_INSTALL"
        \\# usrmerge: the base stages lib, bin, ... as symlinks into usr/, but
        \\# debs may still ship real top-level dirs; fold them in to match
        \\for d in bin sbin lib lib32 lib64; do
        \\  if [ -d "$d" ] && [ ! -L "$d" ] && [ -L "$CRAFT_STAGE/$d" ]; then
        \\    mkdir -p "usr/$d" && cp -a "$d/." "usr/$d/" && rm -rf "$d"
        \\  fi
        \\done
        \\find . ! -type d | while read -r f; do
        \\  if [ -e "$CRAFT_STAGE/$f" ] || [ -L "$CRAFT_STAGE/$f" ]; then rm -f "$f"; fi
        \\done
        },
    });

    // rockcraft's top-level `environment` only applies at runtime, so export
    // the vars for the build scriptlet as well. The /deps dependency cache
    // (CARGO_HOME=/deps and friends) is written to the instance root during
    // the build; move it into the part install so it ships in the image and
    // the test container can run offline.
    var prefix: std.Io.Writer.Allocating = .init(arena.allocator());
    for (config.environment.vars) |v| {
        // keep craft's PATH (craftctl, staged bins) reachable behind the user's
        const tail = if (std.mem.eql(u8, v.name, "PATH")) ":$PATH" else "";
        try prefix.writer.print("export {s}={s}{s}\n", .{ v.name, v.value, tail });
    }
    // craft-parts puts staged binaries on PATH for build scriptlets but never
    // sets LD_LIBRARY_PATH, so shared libs staged by earlier parts wouldn't
    // load at build time
    try prefix.writer.writeAll("export LD_LIBRARY_PATH=\"$CRAFT_STAGE/usr/lib/$(uname -m)-linux-gnu:$CRAFT_STAGE/usr/lib:$CRAFT_STAGE/lib/$(uname -m)-linux-gnu:$CRAFT_STAGE/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}\"\n");

    const test_cmd = test_config.@"test-command" orelse "true";
    const override_build: ?YamlBlockString = .{ .data = try std.mem.concat(arena.allocator(), u8, &.{
        prefix.written(),
        test_config.@"setup-command" orelse "",
        "\n",
        test_cmd,
        // dump first, then merge the cache over it: a project that itself has a
        // deps/ dir would otherwise collide with the moved cache in craftctl default
        "\ncraftctl default\nif [ -d /deps ]; then mkdir -p \"$CRAFT_PART_INSTALL/deps\" && cp -a /deps/. \"$CRAFT_PART_INSTALL/deps/\"; fi\n",
        try organizeScript(arena, rockcraft),
    }) };

    try rockcraft.parts.put(arena.allocator(), "app", .{
        .plugin = "dump",
        .source = ".",
        .after = try arena.allocator().dupe([]const u8, rockcraft.parts.keys()),
        .@"build-packages" = test_config.@"build-deps",
        .@"override-build" = override_build,
    });

    return try serde.yaml.toSlice(arena.allocator(), rockcraft);
}

fn buildImage(arena: *Arena, sub_path: []const u8, rockcraft: []const u8) !void {
    const conf_path = try std.fs.path.join(std.heap.page_allocator, &.{ sub_path, "rockcraft.yaml" });
    try std.fs.cwd().writeFile(.{ .sub_path = conf_path, .data = rockcraft });
    log.info("Creating rock image using the rockcraft.yaml", .{});
    // streamed: pack output (pip/cargo/test logs) easily exceeds the 1 MiB capture cap
    try util.runShellCommandStreamed(arena, &.{ "rockcraft", "pack" }, 0);
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
