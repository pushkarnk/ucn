const std = @import("std");
const util = @import("util");
const Arena = std.heap.ArenaAllocator;
const linux = std.os.linux;
const posix = std.posix;
const UcnConfig = util.UcnConfig;

const FileEvent = enum { added, modified, removed };
const Callback = *const fn (arena: *Arena, name: []const u8, config: UcnConfig) anyerror!void;

pub fn watch(path: []const u8, callback: Callback, arena: *Arena, name: []const u8, config: UcnConfig) !void {
    const fd = try posix.inotify_init1(0);
    defer posix.close(fd);

    const mask = linux.IN.CREATE |
        linux.IN.CLOSE_WRITE |
        linux.IN.DELETE |
        linux.IN.MOVED_FROM |
        linux.IN.MOVED_TO;

    _ = try posix.inotify_add_watch(fd, path, mask);

    var buffer: [4096]u8 align(@alignOf(linux.inotify_event)) = undefined;
    const header_len = @sizeOf(linux.inotify_event);

    while (true) {
        std.debug.print("Watching for file changes in {s}...\n", .{path});
        const n = try posix.read(fd, &buffer);
        var i: usize = 0;

        while (i < n) {
            const event: *const linux.inotify_event = @ptrCast(@alignCast(&buffer[i]));
            if (event.mask & linux.IN.Q_OVERFLOW != 0) {
                std.debug.print("Event queue overflowed, some events may have been lost\n", .{});
                i += header_len + event.len;
                continue;
            }

            const file_name: []const u8 = if (event.len > 0)
                std.mem.sliceTo(buffer[i + header_len ..][0..event.len], 0)
            else
                "";

            if (shouldIgnore(name)) {
                i += header_len + event.len;
                continue;
            }

            if (event.mask & (linux.IN.CREATE |
                linux.IN.CLOSE_WRITE |
                linux.IN.DELETE |
                linux.IN.MOVED_FROM |
                linux.IN.MOVED_TO) != 0)
            {
                std.debug.print("Detected file change: {s}\n", .{file_name});
                try callback(arena, name, config);
            }

            i += header_len + event.len;
        }
    }
}

fn shouldIgnore(name: []const u8) bool {
    if (name.len == 0) return true;
    if (name[0] == '.') return true;
    if (name[name.len - 1] == '~') return true;
    if (std.mem.endsWith(u8, name, ".tmp")) return true;
    const all_digits = for (name) |c| {
        if (!std.ascii.isDigit(c)) break false;
    } else true;
    if (all_digits) return true;
    return false;
}
