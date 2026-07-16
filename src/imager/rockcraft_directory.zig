const std = @import("std");

// Index: "{toolchain-version}-{ubuntu-version}" (e.g. "8.0-24.04").
pub const RockcraftYamlEntry = struct {
    @"toolchain-version": []const u8,
    @"ubuntu-version": []const u8,
    url: []const u8,
};

// Rockcrafts for a single toolchain, indexed by {toolchain-version}:{ubuntu-version}
pub const RockcraftYamls = struct {
    toolchain: []const u8,
    yamls: []const RockcraftYamlEntry,
};

// Directory of rockcraft yamls.
// Lookup: toolchain → (toolchain-version, ubuntu-version) → url.
pub const rockcraft_directory = [_]RockcraftYamls{
    .{
        .toolchain = "dotnet",
        .yamls = &.{
            .{ .@"toolchain-version" = "8.0", .@"ubuntu-version" = "24.04", .url = "https://raw.githubusercontent.com/pushkarnk/dotnet-rocks/refs/heads/main/dotnet-sdk-chiseled/8.0-24.04/rockcraft.yml" },
        },
    },
    .{
        .toolchain = "python",
        .yamls = &.{ .{ .@"toolchain-version" = "3.12", .@"ubuntu-version" = "24.04", .url = "https://raw.githubusercontent.com/canonical/python-rock/refs/heads/main/python/3.12-24.04/rockcraft.yaml" }, .{ .@"toolchain-version" = "3.14", .@"ubuntu-version" = "26.04", .url = "https://raw.githubusercontent.com/canonical/python-rock/refs/heads/main/python/3.14-26.04/rockcraft.yaml" } },
    },
    .{
        .toolchain = "rust",
        .yamls = &.{
            .{ .@"toolchain-version" = "1.75", .@"ubuntu-version" = "24.04", .url = "https://raw.githubusercontent.com/canonical/rust-rock/refs/heads/main/rust/1.75-24.04/rockcraft.yaml" },
            .{ .@"toolchain-version" = "1.80", .@"ubuntu-version" = "24.04", .url = "https://raw.githubusercontent.com/canonical/rust-rock/refs/heads/main/rust/1.80-24.04/rockcraft.yaml" },
            .{ .@"toolchain-version" = "1.93", .@"ubuntu-version" = "26.04", .url = "https://raw.githubusercontent.com/canonical/rust-rock/refs/heads/main/rust/1.93-26.04/rockcraft.yaml" },
        },
    },
    .{
        .toolchain = "java",
        .yamls = &.{
            .{ .@"toolchain-version" = "17", .@"ubuntu-version" = "24.04", .url = "https://raw.githubusercontent.com/canonical/jdk-rock/refs/heads/main/jdk/17-24.04/rockcraft.yaml" },
            .{ .@"toolchain-version" = "21", .@"ubuntu-version" = "24.04", .url = "https://raw.githubusercontent.com/canonical/jdk-rock/refs/heads/main/jdk/21-24.04/rockcraft.yaml" },
            .{ .@"toolchain-version" = "25", .@"ubuntu-version" = "26.04", .url = "https://raw.githubusercontent.com/canonical/jdk-rock/refs/heads/main/jdk/25-26.04/rockcraft.yaml" },
        },
    },
};

// Look up the Rockcraft URL for (toolchain, toolchain-version, ubuntu-version).
pub fn getRockcraftUrl(toolchain: []const u8, toolchain_version: []const u8, ubuntu_version: []const u8) ?[]const u8 {
    for (rockcraft_directory) |entry| {
        if (!std.mem.eql(u8, entry.toolchain, toolchain)) continue;
        for (entry.yamls) |yaml| {
            if (std.mem.eql(u8, yaml.@"toolchain-version", toolchain_version) and
                std.mem.eql(u8, yaml.@"ubuntu-version", ubuntu_version))
            {
                return yaml.url;
            }
        }
    }
    return null;
}
