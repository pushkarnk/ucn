pub const packages = struct {
    pub const @"serde-1.0.1-1DszT_hrDQAURHcyOhR7wEKwqbF8FYl8vN26pKLLCkWn" = struct {
        pub const build_root = "/home/pushkar/.cache/zig/p/serde-1.0.1-1DszT_hrDQAURHcyOhR7wEKwqbF8FYl8vN26pKLLCkWn";
        pub const build_zig = @import("serde-1.0.1-1DszT_hrDQAURHcyOhR7wEKwqbF8FYl8vN26pKLLCkWn");
        pub const deps: []const struct { []const u8, []const u8 } = &.{
        };
    };
    pub const @"zig_yaml-0.2.0-C1161pmrAgC_rL9WzjvgNg7HnmyAMwHsG3Sre0F4haPI" = struct {
        pub const build_root = "/home/pushkar/.cache/zig/p/zig_yaml-0.2.0-C1161pmrAgC_rL9WzjvgNg7HnmyAMwHsG3Sre0F4haPI";
        pub const build_zig = @import("zig_yaml-0.2.0-C1161pmrAgC_rL9WzjvgNg7HnmyAMwHsG3Sre0F4haPI");
        pub const deps: []const struct { []const u8, []const u8 } = &.{
        };
    };
};

pub const root_deps: []const struct { []const u8, []const u8 } = &.{
    .{ "yaml", "zig_yaml-0.2.0-C1161pmrAgC_rL9WzjvgNg7HnmyAMwHsG3Sre0F4haPI" },
    .{ "serde", "serde-1.0.1-1DszT_hrDQAURHcyOhR7wEKwqbF8FYl8vN26pKLLCkWn" },
};
