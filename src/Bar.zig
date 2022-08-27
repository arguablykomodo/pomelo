const std = @import("std");
const parse = @import("ini.zig").parse;
const wordexp = @import("wordexp.zig");
const Block = @import("Block.zig");

const Self = @This();

allocator: std.mem.Allocator,
config_bytes: []const u8,
config: Config,
blocks: std.ArrayList(Block),
bar_writer: std.io.BufferedWriter(4096, if (@import("builtin").is_test) std.ArrayList(u8).Writer else std.fs.File.Writer),

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
    std.sort.sort(Block, self.blocks.items, void, Block.sort);

    return self;
}

pub fn start(self: *Self) !void {
    var flags = std.ArrayList([]const u8).init(self.allocator);

    try flags.append("lemonbar");

    var geometry = std.ArrayList(u8).init(self.allocator);
    defer geometry.deinit();
    var geometry_writer = geometry.writer();
    if (self.config.width) |w| try geometry_writer.print("{s}", .{w});
    try geometry_writer.writeByte('x');
    if (self.config.height) |h| try geometry_writer.print("{s}", .{h});
    try geometry_writer.writeByte('+');
    if (self.config.x) |x| try geometry_writer.print("{s}", .{x});
    try geometry_writer.writeByte('+');
    if (self.config.y) |y| try geometry_writer.print("{s}", .{y});
    try flags.append("-g");
    try flags.append(geometry.items);

    if (self.config.bottom) try flags.append("-b");
    if (self.config.force_docking) try flags.append("-d");
    if (self.config.fonts) |fonts| {
        try flags.append("-f");
        var split = std.mem.split(u8, fonts, ";");
        while (split.next()) |font| try flags.append(font);
    }

    if (self.config.wm_name) |n| {
        try flags.append("-n");
        try flags.append(n);
    }

    if (self.config.line_width) |u| {
        try flags.append("-u");
        try flags.append(u);
    }

    if (self.config.background_color) |b| {
        try flags.append("-B");
        try flags.append(b);
    }

    if (self.config.foreground_color) |f| {
        try flags.append("-F");
        try flags.append(f);
    }

    if (self.config.line_color) |u| {
        try flags.append("-U");
        try flags.append(u);
    }

    var process = std.ChildProcess.init(flags.items, self.allocator);
    process.stdin_behavior = .Pipe;
    try process.spawn();
    self.bar_writer = std.io.bufferedWriter(process.stdin.?.writer());
    for (self.blocks.items) |*block| try block.start(self);
    for (self.blocks.items) |*block| block.thread.join();
    _ = try process.wait();
}

pub fn update(self: *Self) !void {
    var left = std.ArrayList(u8).init(self.allocator);
    defer left.deinit();
    var center = std.ArrayList(u8).init(self.allocator);
    defer center.deinit();
    var right = std.ArrayList(u8).init(self.allocator);
    defer right.deinit();

    for (self.blocks.items) |*block| {
        if (block.content) |content| {
            const writer = switch (block.side) {
                .left => left.writer(),
                .center => center.writer(),
                .right => right.writer(),
            };
            try writer.writeAll(block.prefix.items);
            try writer.writeAll(content);
            try writer.writeAll(block.postfix.items);
        }
    }

    var writer = self.bar_writer.writer();
    try writer.writeAll("%{l}");
    try writer.writeAll(left.items);
    try writer.writeAll("%{c}");
    try writer.writeAll(center.items);
    try writer.writeAll("%{r}");
    try writer.writeAll(right.items);
    try writer.writeByte('\n');
    try self.bar_writer.flush();
}

pub fn deinit(self: *Self) void {
    for (self.blocks.items) |*block| block.deinit();
    self.blocks.deinit();
    self.allocator.free(self.config_bytes);
}
