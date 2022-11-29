const std = @import("std");
const parse = @import("ini.zig").parse;
const wordexp = @import("wordexp.zig");
const Bar = @import("Bar.zig");

const Self = @This();

allocator: std.mem.Allocator,
args: std.ArrayList([]const u8),
mode: Mode,
interval: ?u64,
side: Side,
position: usize,
min_width: usize,
fill_direction: Side,
prefix: std.ArrayList(u8),
content: ?[]const u8,
postfix: std.ArrayList(u8),
thread: std.Thread,

const Mode = enum { once, interval, live };
const mode_map = std.ComptimeStringMap(Mode, .{
    .{ "once", .once },
    .{ "interval", .interval },
    .{ "live", .live },
});

const Side = enum { left, center, right };
const side_map = std.ComptimeStringMap(Side, .{
    .{ "left", .left },
    .{ "center", .center },
    .{ "right", .right },
});

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
    prefix: ?[]const u8 = null,
    postfix: ?[]const u8 = null,
    min_width: usize = 0,
    fill_direction: []const u8 = "left",
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

pub fn init(alloc: std.mem.Allocator, dir: *const std.fs.Dir, filename: []const u8, defaults: *const Bar.Defaults) !Self {
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
            var expansion = try wordexp.wordexp(terminated);
            defer wordexp.wordfree(&expansion);

            const casted = std.mem.span(@ptrCast([*:null]?[*:0]const u8, expansion.we_wordv));
            for (casted) |arg| try args.append(try alloc.dupe(u8, std.mem.span(arg.?)));

            break :blk args;
        },
        .mode = mode_map.get(config.mode) orelse return BlockError.UnknownBlockMode,
        .interval = if (std.mem.eql(u8, config.mode, "interval") and config.interval == null) return error.MissingInterval else config.interval,
        .side = side_map.get(config.side) orelse return BlockError.UnknownBlockSide,
        .position = config.position,
        .min_width = config.min_width,
        .fill_direction = side_map.get(config.fill_direction) orelse return BlockError.UnknownBlockSide,
        .prefix = blk: {
            const writer = prefix.writer();
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
            if (config.prefix) |p| try writer.writeAll(p);
            break :blk prefix;
        },
        .content = null,
        .postfix = blk: {
            const writer = postfix.writer();
            if (config.postfix) |p| try writer.writeAll(p);
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

fn width(content: []const u8) !u64 {
    var real_width: usize = 0;
    var last_pos: usize = 0;
    while (std.mem.indexOfScalarPos(u8, content, last_pos, '%')) |new_pos| {
        real_width += try std.unicode.utf8CountCodepoints(content[last_pos..new_pos]);
        switch (content[new_pos + 1]) {
            '{' => if (std.mem.indexOfScalarPos(u8, content, new_pos + 1, '}')) |end| {
                last_pos = end + 1;
            } else return error.MalformedEscape,
            '%' => {
                real_width += 1;
                last_pos = new_pos + 2;
            },
            else => {
                real_width += 1;
                last_pos = new_pos + 1;
            },
        }
    } else real_width += try std.unicode.utf8CountCodepoints(content[last_pos..]);
    return real_width;
}

fn pad(
    allocator: std.mem.Allocator,
    content: []const u8,
    min_width: u64,
    fill_direction: Side,
) ![]const u8 {
    const real_width = try width(content);
    const new_content = try allocator.alloc(u8, content.len + if (real_width > min_width) 0 else min_width - real_width);
    std.mem.set(u8, new_content, ' ');
    const index = switch (fill_direction) {
        Side.left => 0,
        Side.center => (new_content.len - content.len) / 2,
        Side.right => new_content.len - content.len,
    };
    std.mem.copy(u8, new_content[index..], content);
    return new_content;
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
            const new_content = try stdout.readUntilDelimiterOrEofAlloc(self.allocator, '\n', 1024);
            defer if (new_content) |content| self.allocator.free(content);
            if (self.content) |content| self.allocator.free(content);
            self.content = if (new_content) |content| try pad(self.allocator, content, self.min_width, self.fill_direction) else null;
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
            const new_content = try stdout.readUntilDelimiterOrEofAlloc(self.allocator, '\n', 1024);
            defer if (new_content) |content| self.allocator.free(content);
            if (self.content) |content| self.allocator.free(content);
            self.content = if (new_content) |content| try pad(self.allocator, content, self.min_width, self.fill_direction) else null;
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
                defer if (new_content) |content| self.allocator.free(content);
                if (self.content) |content| self.allocator.free(content);
                self.content = if (new_content) |content| try pad(self.allocator, content, self.min_width, self.fill_direction) else null;
                try bar.update();
                if (@import("builtin").is_test) return;
            }
        },
    }
}

pub fn deinit(self: *const Self) void {
    for (self.args.items) |arg| self.allocator.free(arg);
    self.args.deinit();
    self.prefix.deinit();
    self.postfix.deinit();
    if (self.content) |content| self.allocator.free(content);
}

test "init" {
    var cwd = try std.fs.cwd().openDir("test/blocks", .{});
    defer cwd.close();
    const once = try Self.init(std.testing.allocator, &cwd, "once.ini", &Bar.Defaults{});
    defer once.deinit();
    const interval = try Self.init(std.testing.allocator, &cwd, "interval.ini", &Bar.Defaults{});
    defer interval.deinit();
    const live = try Self.init(std.testing.allocator, &cwd, "live.ini", &Bar.Defaults{});
    defer live.deinit();
    try std.testing.expectError(BlockError.UnknownBlockMode, Self.init(std.testing.allocator, &cwd, "unknown_block.ini", &Bar.Defaults{}));
    try std.testing.expectError(BlockError.UnknownBlockSide, Self.init(std.testing.allocator, &cwd, "unknown_side.ini", &Bar.Defaults{}));
}

test "width" {
    try std.testing.expectEqual(@as(usize, 7), try width("---%%---"));
    try std.testing.expectEqual(@as(usize, 6), try width("---%{foo}---"));
    try std.testing.expectEqual(@as(usize, 7), try width("---%---"));
    try std.testing.expectEqual(@as(usize, 6), try width("--▆---"));
    try std.testing.expectError(error.MalformedEscape, width("---%{---"));
}

test "pad" {
    const left = try pad(std.testing.allocator, "▆▆▆", 6, Side.left);
    defer std.testing.allocator.free(left);
    try std.testing.expectEqualStrings("▆▆▆   ", left);

    const center = try pad(std.testing.allocator, "▆▆▆", 6, Side.center);
    defer std.testing.allocator.free(center);
    try std.testing.expectEqualStrings(" ▆▆▆  ", center);

    const right = try pad(std.testing.allocator, "▆▆▆", 6, Side.right);
    defer std.testing.allocator.free(right);
    try std.testing.expectEqualStrings("   ▆▆▆", right);
}

test "sort" {
    var cwd = try std.fs.cwd().openDir("test/blocks", .{});
    defer cwd.close();
    var blocks = [3]Self{
        try Self.init(std.testing.allocator, &cwd, "live.ini", &Bar.Defaults{}),
        try Self.init(std.testing.allocator, &cwd, "interval.ini", &Bar.Defaults{}),
        try Self.init(std.testing.allocator, &cwd, "once.ini", &Bar.Defaults{}),
    };
    defer for (blocks) |block| block.deinit();
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
