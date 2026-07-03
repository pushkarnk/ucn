const std = @import("std");
const util = @import("util");
const Arena = std.heap.ArenaAllocator;
const linux = std.os.linux;
const posix = std.posix;
const UcnConfig = util.UcnConfig;
const log = std.log;

const FileEvent = enum { added, modified, removed };
const Callback = *const fn (arena: *Arena, name: []const u8, config: UcnConfig) anyerror!void;

const mask = linux.IN.CREATE |
    linux.IN.CLOSE_WRITE |
    linux.IN.DELETE |
    linux.IN.MOVED_FROM |
    linux.IN.MOVED_TO;

const WatchMap = std.AutoHashMapUnmanaged(i32, []const u8);

const default_paths: []const []const u8 = &.{"."};
const empty_ignore: []const []const u8 = &.{};

pub fn watch(callback: Callback, arena: *Arena, name: []const u8, config: UcnConfig) !void {
    const allocator = arena.allocator();
    const fd = try posix.inotify_init1(0);
    defer posix.close(fd);

    const paths = if (config.watch) |w| w.paths else default_paths;
    const ignore = if (config.watch) |w| w.ignore else empty_ignore;

    var watches: WatchMap = .empty;
    for (paths) |path| {
        try addWatchRecursive(allocator, fd, path, &watches, ignore);
    }

    var buffer: [4096]u8 align(@alignOf(linux.inotify_event)) = undefined;
    const header_len = @sizeOf(linux.inotify_event);

    log.info("Watching {d} directories for changes", .{watches.count()});

    while (true) {
        const n = try posix.read(fd, &buffer);
        var i: usize = 0;

        while (i < n) {
            const event: *const linux.inotify_event = @ptrCast(@alignCast(&buffer[i]));
            defer i += header_len + event.len;

            if (event.mask & linux.IN.Q_OVERFLOW != 0) {
                log.warn("Event queue overflowed, some events may have been lost", .{});
                continue;
            }

            const file_name: []const u8 = if (event.len > 0)
                std.mem.sliceTo(buffer[i + header_len ..][0..event.len], 0)
            else
                "";

            if (shouldIgnore(file_name, ignore)) continue;

            const dir = watches.get(event.wd) orelse "?";

            // A new directory appeared: start watching it (and its children) so
            // changes inside it are picked up too.
            if (event.mask & linux.IN.ISDIR != 0 and
                event.mask & (linux.IN.CREATE | linux.IN.MOVED_TO) != 0)
            {
                const new_dir = try std.fs.path.join(allocator, &.{ dir, file_name });
                addWatchRecursive(allocator, fd, new_dir, &watches, ignore) catch |err|
                    log.warn("Failed to watch new directory {s}: {}", .{ new_dir, err });
            }

            if (event.mask & mask != 0) {
                log.info("Detected change in {s}/{s}", .{ dir, file_name });
                try callback(arena, name, config);
            }
        }
    }
}

// Adds a watch for `path` and, recursively, for every (non-ignored) directory
// beneath it. `path` may also be a regular file, in which case only that file
// is watched.
fn addWatchRecursive(allocator: std.mem.Allocator, fd: i32, path: []const u8, watches: *WatchMap, ignore: []const []const u8) !void {
    const wd = try posix.inotify_add_watch(fd, path, mask);
    try watches.put(allocator, wd, try allocator.dupe(u8, path));

    var dir = std.fs.cwd().openDir(path, .{ .iterate = true }) catch |err| switch (err) {
        // A regular file was watched directly; nothing to recurse into.
        error.NotDir => return,
        else => {
            log.warn("Cannot open {s} for watching: {}", .{ path, err });
            return;
        },
    };
    defer dir.close();

    var it = dir.iterate();
    while (try it.next()) |entry| {
        if (entry.kind != .directory) continue;
        if (shouldIgnoreDir(entry.name, ignore)) continue;
        const sub_path = try std.fs.path.join(allocator, &.{ path, entry.name });
        try addWatchRecursive(allocator, fd, sub_path, watches, ignore);
    }
}

fn shouldIgnore(name: []const u8, ignore: []const []const u8) bool {
    if (name.len == 0) return true;
    if (name[0] == '.') return true;
    if (name[name.len - 1] == '~') return true;
    if (std.mem.endsWith(u8, name, ".tmp")) return true;
    const all_digits = for (name) |c| {
        if (!std.ascii.isDigit(c)) break false;
    } else true;
    if (all_digits) return true;
    if (isIgnored(name, ignore)) return true;
    return false;
}

fn shouldIgnoreDir(name: []const u8, ignore: []const []const u8) bool {
    if (name.len == 0) return true;
    if (name[0] == '.') return true;
    if (std.mem.endsWith(u8, name, ".egg-info")) return true;
    const ignored = [_][]const u8{ "__pycache__", "vendor", "deps", "obj", "bin" };
    for (ignored) |d| {
        if (std.mem.eql(u8, name, d)) return true;
    }
    if (isIgnored(name, ignore)) return true;
    return false;
}

// Whether `name` matches any entry in the user-configured ignore list.
fn isIgnored(name: []const u8, ignore: []const []const u8) bool {
    for (ignore) |entry| {
        if (std.mem.eql(u8, name, entry)) return true;
    }
    return false;
}
