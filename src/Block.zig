const std = @import("std");
const parse = @import("ini.zig").parse;

const Self = @This();

allocator: std.mem.Allocator,
config_bytes: []const u8,
config: Config,

const Config = struct {
    command: []const u8 = "",
    type: []const u8 = "", // once | interval | live
    interval: ?usize = null, // must exist if type == "interval"
    side: []const u8 = "", // left | center | right
    position: usize = 0,

    left_click: ?[]const u8 = null,
    middle_click: ?[]const u8 = null,
    right_click: ?[]const u8 = null,
    scroll_up: ?[]const u8 = null,
    scroll_down: ?[]const u8 = null,

    margin_left: ?usize = null,
    margin_right: ?usize = null,
    padding: ?usize = null,
    underline: ?bool = null,
    overline: ?bool = null,
    background_color: ?[]const u8 = null,
    foreground_color: ?[]const u8 = null,
    line_color: ?[]const u8 = null,
};

pub fn init(alloc: std.mem.Allocator, dir: *std.fs.Dir, filename: []const u8) !Self {
    var self: Self = undefined;
    self.allocator = alloc;
    self.config_bytes = try dir.readFileAlloc(self.allocator, filename, 1024 * 5);
    self.config = try parse(Config, self.config_bytes);
    return self;
}

pub fn deinit(self: *Self) void {
    self.allocator.free(self.config_bytes);
}
