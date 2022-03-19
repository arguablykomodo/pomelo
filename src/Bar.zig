const std = @import("std");
const parse = @import("ini.zig").parse;
const wordexp = @import("wordexp.zig");
const Block = @import("Block.zig");

const Self = @This();

allocator: std.mem.Allocator,
config_bytes: []const u8,
config: Config,
blocks: std.ArrayList(Block),

const Config = struct {
    width: ?usize = null,
    height: ?usize = null,
    x: ?usize = null,
    y: ?usize = null,
    bottom: bool = false,
    force_docking: bool = false,
    fonts: ?[]const u8 = null,
    wm_name: ?[]const u8 = null,
    line_width: ?usize = null,
    background_color: ?[]const u8 = null,
    foreground_color: ?[]const u8 = null,
    line_color: ?[]const u8 = null,

    defaults: Defaults = .{},

    const Defaults = struct {
        margin_left: usize = 0,
        margin_right: usize = 0,
        padding: usize = 0,
        underline: bool = false,
        overline: bool = false,
        background_color: ?[]const u8 = null,
    };
};

pub fn init(alloc: std.mem.Allocator) !Self {
    var self: Self = undefined;
    self.allocator = alloc;

    var config_dir = x: {
        var path = try wordexp.wordexp("${XDG_CONFIG_DIR:-$HOME/.config}/pomelo");
        defer wordexp.wordfree(&path);
        break :x try std.fs.openDirAbsolute(std.mem.span(path.we_wordv[0]), .{});
    };
    defer config_dir.close();

    self.config_bytes = try config_dir.readFileAlloc(self.allocator, "pomelo.ini", 1024 * 5);
    self.config = try parse(Config, self.config_bytes);

    self.blocks = std.ArrayList(Block).init(self.allocator);
    var blocks_dir = try config_dir.openDir("blocks", .{ .access_sub_paths = false, .iterate = true });
    defer blocks_dir.close();
    var blocks_iterator = blocks_dir.iterate();
    while (try blocks_iterator.next()) |block_file| {
        if (block_file.kind != .File) continue;
        try self.blocks.append(try Block.init(self.allocator, &blocks_dir, block_file.name));
    }

    return self;
}

pub fn deinit(self: *Self) void {
    for (self.blocks.items) |*block| {
        block.deinit();
    }
    self.blocks.deinit();
    self.allocator.free(self.config_bytes);
}
