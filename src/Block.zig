const std = @import("std");
const parse = @import("ini.zig").parse;
const wordexp = @import("wordexp.zig");
const Bar = @import("Bar.zig");

const Self = @This();

allocator: std.mem.Allocator,
args: std.ArrayList([]const u8),
mode: Mode,
interval: ?u64 = null,
side: Side,
position: usize = 0,
prefix: std.ArrayList(u8),
content: ?[]const u8,
postfix: std.ArrayList(u8),
thread: std.Thread,

const Mode = enum { once, interval, live };
const Side = enum { left, center, right };

const Config = struct {
    command: []const u8 = "",
    mode: []const u8 = "",
    interval: ?u64 = null,
    side: []const u8 = "",
    position: usize = 0,

    left_click: ?[]const u8 = null,
    middle_click: ?[]const u8 = null,
    right_click: ?[]const u8 = null,
    scroll_up: ?[]const u8 = null,
    scroll_down: ?[]const u8 = null,

    margin_left: ?[]const u8 = null,
    margin_right: ?[]const u8 = null,
    padding: ?[]const u8 = null,
    underline: ?bool = null,
    overline: ?bool = null,
    background_color: ?[]const u8 = null,
    foreground_color: ?[]const u8 = null,
    line_color: ?[]const u8 = null,
};

const BlockError = error{
    UnknownBlockMode,
    UnknownBlockSide,
};

pub fn init(alloc: std.mem.Allocator, dir: *std.fs.Dir, filename: []const u8, defaults: *const Bar.Defaults) !Self {
    const config_bytes = try dir.readFileAlloc(alloc, filename, 1024 * 5);
    defer alloc.free(config_bytes);
    var config = try parse(Config, config_bytes);

    if (config.margin_left == null) config.margin_left = defaults.*.margin_left;
    if (config.margin_right == null) config.margin_right = defaults.*.margin_right;
    if (config.padding == null) config.padding = defaults.*.padding;
    if (config.underline == null) config.underline = defaults.*.underline;
    if (config.overline == null) config.overline = defaults.*.overline;
    if (config.background_color == null) config.background_color = defaults.*.background_color;

    var args = std.ArrayList([]const u8).init(alloc);
    errdefer {
        for (args.items) |arg| alloc.free(arg);
        args.deinit();
    }

    var prefix = std.ArrayList(u8).init(alloc);
    errdefer prefix.deinit();

    var postfix = std.ArrayList(u8).init(alloc);
    errdefer postfix.deinit();

    return Self{
        .allocator = alloc,
        .args = blk: {
            if (std.mem.eql(u8, config.command, "")) return error.MissingCommand;

            const terminated = try std.mem.concat(alloc, u8, &.{ config.command, "\x00" });
            defer alloc.free(terminated);
            var expansion = try wordexp.wordexp(@ptrCast([*c]const u8, terminated));
            defer wordexp.wordfree(&expansion);

            const casted = std.mem.span(@ptrCast([*:null]?[*:0]const u8, expansion.we_wordv));
            for (casted) |arg| try args.append(try alloc.dupe(u8, std.mem.span(arg.?)));

            break :blk args;
        },
        .mode = blk: {
            if (std.mem.eql(u8, config.mode, "once")) break :blk Mode.once;
            if (std.mem.eql(u8, config.mode, "interval")) break :blk Mode.interval;
            if (std.mem.eql(u8, config.mode, "live")) break :blk Mode.live;
            return BlockError.UnknownBlockMode;
        },
        .interval = if (std.mem.eql(u8, config.mode, "interval") and config.interval == null) return error.MissingInterval else config.interval,
        .side = blk: {
            if (std.mem.eql(u8, config.side, "left")) break :blk Side.left;
            if (std.mem.eql(u8, config.side, "center")) break :blk Side.center;
            if (std.mem.eql(u8, config.side, "right")) break :blk Side.right;
            return BlockError.UnknownBlockSide;
        },
        .position = config.position,
        .prefix = blk: {
            var writer = prefix.writer();
            if (config.margin_left) |o| try writer.print("%{{O{s}}}", .{o});
            if (config.left_click) |a| try writer.print("%{{A1:{s}:}}", .{a});
            if (config.middle_click) |a| try writer.print("%{{A2:{s}:}}", .{a});
            if (config.right_click) |a| try writer.print("%{{A3:{s}:}}", .{a});
            if (config.scroll_up) |a| try writer.print("%{{A4:{s}:}}", .{a});
            if (config.scroll_down) |a| try writer.print("%{{A5:{s}:}}", .{a});
            if (config.background_color) |b| try writer.print("%{{B{s}}}", .{b});
            if (config.foreground_color) |f| try writer.print("%{{F{s}}}", .{f});
            if (config.line_color) |u| try writer.print("%{{U{s}}}", .{u});
            if (config.underline.?) try writer.writeAll("%{+u}");
            if (config.overline.?) try writer.writeAll("%{+o}");
            if (config.padding) |o| try writer.print("%{{O{s}}}", .{o});
            break :blk prefix;
        },
        .content = null,
        .postfix = blk: {
            var writer = postfix.writer();
            if (config.padding) |o| try writer.print("%{{O{s}}}", .{o});
            if (config.overline.?) try writer.writeAll("%{-o}");
            if (config.underline.?) try writer.writeAll("%{-u}");
            if (config.line_color) |_| try writer.writeAll("%{U-}");
            if (config.foreground_color) |_| try writer.writeAll("%{F-}");
            if (config.background_color) |_| try writer.writeAll("%{B-}");
            if (config.scroll_down) |_| try writer.writeAll("%{A}");
            if (config.scroll_up) |_| try writer.writeAll("%{A}");
            if (config.right_click) |_| try writer.writeAll("%{A}");
            if (config.middle_click) |_| try writer.writeAll("%{A}");
            if (config.left_click) |_| try writer.writeAll("%{A}");
            if (config.margin_right) |o| try writer.print("%{{O{s}}}", .{o});
            break :blk postfix;
        },
        .thread = undefined,
    };
}

pub fn sort(comptime _: type, lhs: Self, rhs: Self) bool {
    return lhs.position < rhs.position;
}

pub fn start(self: *Self, bar: *Bar) !void {
    self.thread = try std.Thread.spawn(.{}, Self.threaded, .{ self, bar });
}

fn threaded(self: *Self, bar: *Bar) !void {
    switch (self.mode) {
        .once => {
            var process = std.ChildProcess.init(self.args.items, self.allocator);
            process.stdin_behavior = .Ignore;
            process.stdout_behavior = .Pipe;
            process.stderr_behavior = .Inherit;
            try process.spawn();
            const stdout = process.stdout.?.reader();
            if (self.content) |content| self.allocator.free(content);
            self.content = try stdout.readUntilDelimiterOrEofAlloc(self.allocator, '\n', 1024) orelse null;
            try bar.update();
            _ = try process.wait(); // TODO: inspect exit condition
        },
        .interval => while (true) {
            var process = std.ChildProcess.init(self.args.items, self.allocator);
            process.stdin_behavior = .Ignore;
            process.stdout_behavior = .Pipe;
            process.stderr_behavior = .Inherit;
            try process.spawn();
            const stdout = process.stdout.?.reader();
            if (self.content) |content| self.allocator.free(content);
            self.content = try stdout.readUntilDelimiterOrEofAlloc(self.allocator, '\n', 1024) orelse null;
            try bar.update();
            _ = try process.wait(); // TODO: inspect exit condition
            std.time.sleep(self.interval.? * std.time.ns_per_ms);
            if (@import("builtin").is_test) return;
        },
        .live => {
            var process = std.ChildProcess.init(self.args.items, self.allocator);
            process.stdin_behavior = .Ignore;
            process.stdout_behavior = .Pipe;
            process.stderr_behavior = .Inherit;
            try process.spawn();
            const stdout = process.stdout.?.reader();
            while (true) {
                const new_content = try stdout.readUntilDelimiterOrEofAlloc(self.allocator, '\n', 1024);
                if (self.content) |content| self.allocator.free(content);
                self.content = new_content;
                try bar.update();
                if (@import("builtin").is_test) return;
            }
        },
    }
}

pub fn deinit(self: *Self) void {
    for (self.args.items) |arg| self.allocator.free(arg);
    self.args.deinit();
    self.prefix.deinit();
    self.postfix.deinit();
    if (self.content) |content| self.allocator.free(content);
}

test "init" {
    var cwd = try std.fs.cwd().openDir("test/blocks", .{});
    defer cwd.close();
    var block = try Self.init(std.testing.allocator, &cwd, "once.ini", &Bar.Defaults{});
    block.deinit();
    block = try Self.init(std.testing.allocator, &cwd, "interval.ini", &Bar.Defaults{});
    block.deinit();
    block = try Self.init(std.testing.allocator, &cwd, "live.ini", &Bar.Defaults{});
    block.deinit();
    try std.testing.expectError(BlockError.UnknownBlockMode, Self.init(std.testing.allocator, &cwd, "unknown_block.ini", &Bar.Defaults{}));
    try std.testing.expectError(BlockError.UnknownBlockSide, Self.init(std.testing.allocator, &cwd, "unknown_side.ini", &Bar.Defaults{}));
}

test "sort" {
    var cwd = try std.fs.cwd().openDir("test/blocks", .{});
    defer cwd.close();
    var blocks = [3]Self{
        try Self.init(std.testing.allocator, &cwd, "live.ini", &Bar.Defaults{}),
        try Self.init(std.testing.allocator, &cwd, "interval.ini", &Bar.Defaults{}),
        try Self.init(std.testing.allocator, &cwd, "once.ini", &Bar.Defaults{}),
    };
    defer for (blocks) |*block| block.deinit();
    std.sort.sort(Self, &blocks, void, Self.sort);
    try std.testing.expectEqual(Mode.once, blocks[0].mode);
    try std.testing.expectEqual(Mode.interval, blocks[1].mode);
    try std.testing.expectEqual(Mode.live, blocks[2].mode);
}

test "start" {
    var output = std.ArrayList(u8).init(std.testing.allocator);
    defer output.deinit();
    var bar = Bar{
        .allocator = std.testing.allocator,
        .config_bytes = try std.testing.allocator.alloc(u8, 8),
        .config = .{},
        .blocks = std.ArrayList(Self).init(std.testing.allocator),
        .bar_writer = std.io.bufferedWriter(output.writer()),
    };
    defer bar.deinit();

    var cwd = try std.fs.cwd().openDir("test/blocks", .{});
    defer cwd.close();

    try bar.blocks.append(try Self.init(std.testing.allocator, &cwd, "once.ini", &Bar.Defaults{}));
    try bar.blocks.append(try Self.init(std.testing.allocator, &cwd, "interval.ini", &Bar.Defaults{}));
    try bar.blocks.append(try Self.init(std.testing.allocator, &cwd, "live.ini", &Bar.Defaults{}));

    try bar.blocks.items[0].start(&bar);
    bar.blocks.items[0].thread.join();
    try std.testing.expectEqualStrings("once", bar.blocks.items[0].content.?);

    try bar.blocks.items[1].start(&bar);
    bar.blocks.items[1].thread.join();
    try std.testing.expectEqualStrings("interval", bar.blocks.items[1].content.?);

    try bar.blocks.items[2].start(&bar);
    bar.blocks.items[2].thread.join();
    try std.testing.expectEqualStrings("live", bar.blocks.items[2].content.?);
}
