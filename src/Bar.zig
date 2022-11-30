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
should_update: std.atomic.Atomic(u32),

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

pub fn init(config_dir: std.fs.Dir, alloc: std.mem.Allocator) !Self {
    const config_bytes = try config_dir.readFileAlloc(alloc, "pomelo.ini", 1024 * 5);
    errdefer alloc.free(config_bytes);
    const config = try parse(Config, config_bytes);

    var blocks = std.ArrayList(Block).init(alloc);
    errdefer {
        for (blocks.items) |block| block.deinit();
        blocks.deinit();
    }
    var blocks_dir = try config_dir.openIterableDir("blocks", .{ .access_sub_paths = false });
    defer blocks_dir.close();
    var blocks_iterator = blocks_dir.iterate();
    while (try blocks_iterator.next()) |block_file| {
        if (block_file.kind != .File) continue;
        try blocks.append(try Block.init(alloc, &blocks_dir.dir, block_file.name, &config.defaults));
    }
    std.sort.sort(Block, blocks.items, void, Block.sort);

    return Self{
        .allocator = alloc,
        .config_bytes = config_bytes,
        .config = config,
        .blocks = blocks,
        .bar_writer = undefined,
        .should_update = std.atomic.Atomic(u32).init(0),
    };
}

fn parseFlags(alloc: std.mem.Allocator, config: Config) ![][]const u8 {
    var flags = std.ArrayList([]const u8).init(alloc);
    errdefer flags.deinit();

    try flags.append("lemonbar");

    var geometry = std.ArrayList(u8).init(alloc);
    errdefer geometry.deinit();
    var geometry_writer = geometry.writer();
    if (config.width) |w| try geometry_writer.writeAll(w);
    try geometry_writer.writeByte('x');
    if (config.height) |h| try geometry_writer.writeAll(h);
    try geometry_writer.writeByte('+');
    if (config.x) |x| try geometry_writer.writeAll(x);
    try geometry_writer.writeByte('+');
    if (config.y) |y| try geometry_writer.writeAll(y);
    try flags.appendSlice(&.{ "-g", geometry.toOwnedSlice() });

    if (config.bottom) try flags.append("-b");
    if (config.force_docking) try flags.append("-d");
    if (config.fonts) |fonts| {
        try flags.append("-f");
        var split = std.mem.split(u8, fonts, ";");
        while (split.next()) |font| try flags.append(font);
    }
    if (config.wm_name) |n| try flags.appendSlice(&.{ "-n", n });
    if (config.line_width) |u| try flags.appendSlice(&.{ "-u", u });
    if (config.background_color) |b| try flags.appendSlice(&.{ "-B", b });
    if (config.foreground_color) |f| try flags.appendSlice(&.{ "-F", f });
    if (config.line_color) |u| try flags.appendSlice(&.{ "-U", u });

    return flags.toOwnedSlice();
}

pub fn start(self: *Self) !void {
    const flags = try parseFlags(self.allocator, self.config);
    defer {
        self.allocator.free(flags[2]);
        self.allocator.free(flags);
    }

    var process = std.ChildProcess.init(flags, self.allocator);
    process.stdin_behavior = .Pipe;
    try process.spawn();
    self.bar_writer = std.io.bufferedWriter(process.stdin.?.writer());
    for (self.blocks.items) |*block| try block.start(&self.should_update);

    while (true) {
        std.Thread.Futex.wait(&self.should_update, 0);
        try self.update();
        self.should_update.store(0, .Release);
    }

    for (self.blocks.items) |block| block.thread.join();
    _ = try process.wait();
}

pub fn update(self: *Self) !void {
    var left = std.ArrayList(u8).init(self.allocator);
    defer left.deinit();
    var center = std.ArrayList(u8).init(self.allocator);
    defer center.deinit();
    var right = std.ArrayList(u8).init(self.allocator);
    defer right.deinit();

    for (self.blocks.items) |block| {
        if (block.content) |content| {
            const writer = switch (block.side) {
                .left => left.writer(),
                .center => center.writer(),
                .right => right.writer(),
            };
            try writer.print("{s}{s}{s}", .{ block.prefix.items, content, block.postfix.items });
        }
    }

    try self.bar_writer.writer().print(
        "%{{l}}{s}%{{c}}{s}%{{r}}{s}\n",
        .{ left.items, center.items, right.items },
    );
    try self.bar_writer.flush();
}

pub fn deinit(self: *const Self) void {
    for (self.blocks.items) |block| block.deinit();
    self.blocks.deinit();
    self.allocator.free(self.config_bytes);
}

test "init" {
    var cwd = try std.fs.cwd().openDir("example", .{});
    defer cwd.close();

    const bar = try Self.init(cwd, std.testing.allocator);
    defer bar.deinit();
}

test "parseFlags" {
    const config = Config{
        .width = "10",
        .height = "10",
        .x = "10",
        .y = "10",
        .bottom = true,
        .force_docking = true,
        .fonts = "foo;bar",
        .wm_name = "baz",
        .line_width = "2",
        .background_color = "#000",
        .foreground_color = "#fff",
        .line_color = "#fff",
        .defaults = .{},
    };

    const flags = try parseFlags(std.testing.allocator, config);
    defer {
        std.testing.allocator.free(flags[2]);
        std.testing.allocator.free(flags);
    }
}
