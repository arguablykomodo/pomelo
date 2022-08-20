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
    width: ?[]const u8 = null,
    height: ?[]const u8 = null,
    x: ?[]const u8 = null,
    y: ?[]const u8 = null,
    bottom: bool = false,
    force_docking: bool = false,
    fonts: ?[]const u8 = null,
    wm_name: ?[]const u8 = null,
    line_width: ?[]const u8 = null,
    background_color: ?[]const u8 = null,
    foreground_color: ?[]const u8 = null,
    line_color: ?[]const u8 = null,

    defaults: Defaults = .{},
};

pub const Defaults = struct {
    margin_left: ?[]const u8 = null,
    margin_right: ?[]const u8 = null,
    padding: ?[]const u8 = null,
    underline: bool = false,
    overline: bool = false,
    background_color: ?[]const u8 = null,
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
    var blocks_dir = try config_dir.openIterableDir("blocks", .{ .access_sub_paths = false });
    defer blocks_dir.close();
    var blocks_iterator = blocks_dir.iterate();
    while (try blocks_iterator.next()) |block_file| {
        if (block_file.kind != .File) continue;
        try self.blocks.append(try Block.init(self.allocator, &blocks_dir.dir, block_file.name, &self.config.defaults));
    }

    return self;
}

pub fn start(self: *Self) !void {
    for (self.blocks.items) |*block| {
        try block.start();
        std.debug.print("{s}{s}{s}", .{ block.prefix.items, block.content, block.postfix.items });
    }
}

pub fn deinit(self: *Self) void {
    for (self.blocks.items) |*block| {
        block.deinit();
    }
    self.blocks.deinit();
    self.allocator.free(self.config_bytes);
}
