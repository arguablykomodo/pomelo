const std = @import("std");
const xev = @import("xev");
const ini = @import("ini.zig");
const Block = @import("Block.zig");

pub const Config = struct {
    pub const Defaults = struct {
        margin_left: usize = 0,
        margin_right: usize = 0,
        padding: usize = 0,
        prefix: ?[]const u8 = null,
        postfix: ?[]const u8 = null,

        underline: bool = false,
        overline: bool = false,
        background_color: ?[]const u8 = null,
    };

    width: ?usize = null,
    height: ?usize = null,
    x: ?usize = null,
    y: ?usize = null,
    bottom: bool = false,

    force_docking: bool = false,
    clickable_areas: ?usize = null,
    wm_name: ?[]const u8 = null,

    fonts: ?[]const u8 = null,
    vertical_offset: ?isize = null,

    line_width: ?usize = null,
    background_color: ?[]const u8 = null,
    foreground_color: ?[]const u8 = null,
    line_color: ?[]const u8 = null,

    defaults: Defaults = .{},
};

alloc: std.mem.Allocator,
dir: std.fs.Dir,
defaults: Config.Defaults,
blocks: std.ArrayList(Block),
loop: *xev.Loop,
completion: xev.Completion,

flags_arena: std.heap.ArenaAllocator,
lemonbar: std.ChildProcess,

pub fn init(alloc: std.mem.Allocator, dir: std.fs.Dir, loop: *xev.Loop) !@This() {
    const config_bytes = try dir.readFileAlloc(alloc, "pomelo.ini", 1024 * 5);
    defer alloc.free(config_bytes);
    const config = try ini.parse(Config, config_bytes);

    var flags_arena = std.heap.ArenaAllocator.init(alloc);
    errdefer flags_arena.deinit();
    const flags_alloc = flags_arena.allocator();
    var flags = std.ArrayList([]const u8).init(flags_alloc);
    try flags.append("lemonbar");
    var geometry = std.ArrayList(u8).init(flags_alloc);
    var geometry_writer = geometry.writer();
    if (config.width) |w| try geometry_writer.print("{}", .{w});
    try geometry_writer.writeByte('x');
    if (config.height) |h| try geometry_writer.print("{}", .{h});
    try geometry_writer.writeByte('+');
    if (config.x) |x| try geometry_writer.print("{}", .{x});
    try geometry_writer.writeByte('+');
    if (config.y) |y| try geometry_writer.print("{}", .{y});
    try flags.appendSlice(&.{ "-g", geometry.items });
    if (config.bottom) try flags.append("-b");
    if (config.force_docking) try flags.append("-d");
    if (config.clickable_areas) |a| try flags.appendSlice(&.{ "-a", try std.fmt.allocPrint(flags_alloc, "{}", .{a}) });
    if (config.wm_name) |n| try flags.appendSlice(&.{ "-n", try flags_alloc.dupe(u8, n) });
    if (config.fonts) |fonts| {
        var split = std.mem.split(u8, fonts, ";");
        while (split.next()) |font| try flags.appendSlice(&.{ "-f", try flags_alloc.dupe(u8, font) });
    }
    if (config.vertical_offset) |o| try flags.appendSlice(&.{ "-o", try std.fmt.allocPrint(flags_alloc, "{}", .{o}) });
    if (config.line_width) |u| try flags.appendSlice(&.{ "-u", try std.fmt.allocPrint(flags_alloc, "{}", .{u}) });
    if (config.background_color) |b| try flags.appendSlice(&.{ "-B", try flags_alloc.dupe(u8, b) });
    if (config.foreground_color) |f| try flags.appendSlice(&.{ "-F", try flags_alloc.dupe(u8, f) });
    if (config.line_color) |u| try flags.appendSlice(&.{ "-U", try flags_alloc.dupe(u8, u) });

    var lemonbar = std.ChildProcess.init(flags.items, alloc);
    lemonbar.stdin_behavior = .Pipe;

    return @This(){
        .alloc = alloc,
        .dir = dir,
        .defaults = config.defaults,
        .blocks = std.ArrayList(Block).init(alloc),
        .loop = loop,
        .completion = undefined,
        .flags_arena = flags_arena,
        .lemonbar = lemonbar,
    };
}

pub fn deinit(self: *@This()) void {
    self.flags_arena.deinit();
    for (self.blocks.items) |*block| block.deinit();
    self.blocks.deinit();
    _ = self.lemonbar.kill() catch unreachable;
}

pub fn run(self: *@This()) !void {
    var blocks_dir = try self.dir.openIterableDir("blocks", .{ .access_sub_paths = false });
    defer blocks_dir.close();
    var blocks_iterator = blocks_dir.iterate();
    while (try blocks_iterator.next()) |block_file| {
        if (block_file.kind != .file) continue;
        try self.blocks.append(try Block.init(self.alloc, &blocks_dir.dir, self, block_file.name));
    }
    std.sort.block(Block, self.blocks.items, {}, Block.sort);
    for (self.blocks.items) |*block| try block.run();
    try self.lemonbar.spawn();
    self.flags_arena.deinit();
}

pub fn update(self: *@This()) !void {
    var left = std.ArrayList(u8).init(self.alloc);
    defer left.deinit();
    var center = std.ArrayList(u8).init(self.alloc);
    defer center.deinit();
    var right = std.ArrayList(u8).init(self.alloc);
    defer right.deinit();

    for (self.blocks.items) |*block| {
        if (block.content) |content| {
            const writer = switch (block.side) {
                .left => left.writer(),
                .center => center.writer(),
                .right => right.writer(),
            };
            try writer.print("{s}{s}{s}", .{ block.prefix, content, block.postfix });
        }
    }

    var bar_writer = std.io.bufferedWriter(self.lemonbar.stdin.?.writer());
    try bar_writer.writer().print(
        "%{{l}}{s}%{{c}}{s}%{{r}}{s}\n",
        .{ left.items, center.items, right.items },
    );
    try bar_writer.flush();
}
