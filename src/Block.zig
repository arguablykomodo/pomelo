const std = @import("std");
const xev = @import("xev");
const ini = @import("ini.zig");
const wordexp = @import("wordexp.zig");
const Bar = @import("Bar.zig");

const Config = struct {
    const Mode = enum { once, interval, live };
    const Side = enum { left, center, right };

    command: []const u8,
    mode: Mode,
    interval: ?u64 = null,
    side: Side,
    position: usize = 0,

    left_click: ?[]const u8 = null,
    middle_click: ?[]const u8 = null,
    right_click: ?[]const u8 = null,
    scroll_up: ?[]const u8 = null,
    scroll_down: ?[]const u8 = null,

    min_width: usize = 0,
    fill_direction: Side = Side.left,

    margin_left: ?usize = null,
    margin_right: ?usize = null,
    padding: ?usize = null,
    prefix: ?[]const u8 = null,
    postfix: ?[]const u8 = null,

    underline: ?bool = null,
    overline: ?bool = null,
    background_color: ?[]const u8 = null,
    foreground_color: ?[]const u8 = null,
    line_color: ?[]const u8 = null,
};

alloc: std.mem.Allocator,
bar: *Bar,

side: Config.Side,
position: usize,
min_width: usize,
fill_direction: Config.Side,

prefix: []const u8,
postfix: []const u8,
content: ?[]const u8,

args: []const []const u8,
process: ?std.ChildProcess,
loop: *xev.Loop,
completion: xev.Completion,

data: union(Config.Mode) {
    once: struct { process: xev.Process },
    interval: struct {
        interval: u64,
        process: xev.Process,
        timer: xev.Timer,
    },
    live: struct {
        buffer: std.ArrayList(u8),
        file: xev.File,
    },
},

pub fn init(
    alloc: std.mem.Allocator,
    dir: *const std.fs.Dir,
    bar: *Bar,
    filename: []const u8,
) !@This() {
    const config_bytes = try dir.readFileAlloc(alloc, filename, 1024 * 5);
    defer alloc.free(config_bytes);
    var config = try ini.parse(Config, config_bytes);

    if (config.mode == .interval and config.interval == null) return error.MissingInterval;
    config.margin_left = config.margin_left orelse bar.defaults.margin_left;
    config.margin_right = config.margin_right orelse bar.defaults.margin_right;
    config.padding = config.padding orelse bar.defaults.padding;
    config.prefix = config.prefix orelse bar.defaults.prefix;
    config.postfix = config.postfix orelse bar.defaults.postfix;
    config.underline = config.underline orelse bar.defaults.underline;
    config.overline = config.overline orelse bar.defaults.overline;
    config.background_color = config.background_color orelse bar.defaults.background_color;

    return @This(){
        .alloc = alloc,
        .bar = bar,

        .side = config.side,
        .position = config.position,
        .min_width = config.min_width,
        .fill_direction = config.fill_direction,

        .prefix = try buildPrefix(alloc, config),
        .postfix = try buildPostfix(alloc, config),
        .content = null,

        .args = try expandCommand(alloc, config.command),
        .process = null,
        .loop = bar.loop,
        .completion = undefined,

        .data = switch (config.mode) {
            .once => .{ .once = .{ .process = undefined } },
            .interval => .{ .interval = .{
                .interval = config.interval.?,
                .process = undefined,
                .timer = try xev.Timer.init(),
            } },
            .live => .{ .live = .{
                .buffer = std.ArrayList(u8).init(alloc),
                .file = undefined,
            } },
        },
    };
}

fn expandCommand(alloc: std.mem.Allocator, command: []const u8) ![]const []const u8 {
    var args = std.ArrayList([]const u8).init(alloc);
    defer {
        for (args.items) |arg| alloc.free(arg);
        args.deinit();
    }
    const terminated = try std.mem.concat(alloc, u8, &.{ command, "\x00" });
    defer alloc.free(terminated);
    var expansion = try wordexp.wordexp(terminated);
    defer wordexp.wordfree(&expansion);
    const casted: [*:null]?[*:0]const u8 = @ptrCast(expansion.we_wordv);
    for (std.mem.span(casted)) |arg| try args.append(try alloc.dupe(u8, std.mem.span(arg.?)));
    return try args.toOwnedSlice();
}

fn buildPrefix(alloc: std.mem.Allocator, config: Config) ![]const u8 {
    var prefix = std.ArrayList(u8).init(alloc);
    defer prefix.deinit();
    const writer = prefix.writer();
    if (config.margin_left.? != 0) try writer.print("%{{O{}}}", .{config.margin_left.?});
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
    if (config.padding.? != 0) try writer.print("%{{O{}}}", .{config.padding.?});
    if (config.prefix) |p| try writer.writeAll(p);
    return prefix.toOwnedSlice();
}

fn buildPostfix(alloc: std.mem.Allocator, config: Config) ![]const u8 {
    var postfix = std.ArrayList(u8).init(alloc);
    defer postfix.deinit();
    const writer = postfix.writer();
    if (config.postfix) |p| try writer.writeAll(p);
    if (config.padding.? != 0) try writer.print("%{{O{}}}", .{config.padding.?});
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
    if (config.margin_right.? != 0) try writer.print("%{{O{}}}", .{config.margin_right.?});
    return postfix.toOwnedSlice();
}

pub fn deinit(self: *@This()) void {
    self.alloc.free(self.prefix);
    self.alloc.free(self.postfix);
    if (self.content) |content| self.alloc.free(content);

    for (self.args) |arg| self.alloc.free(arg);
    self.alloc.free(self.args);
    if (self.process) |*process| _ = process.kill() catch unreachable;
    var completion: xev.Completion = undefined;
    self.loop.cancel(&self.completion, &completion, void, null, cancelCallback);

    switch (self.data) {
        .once => |*data| data.process.deinit(),
        .interval => |*data| {
            data.process.deinit();
            data.timer.deinit();
        },
        .live => |*data| {
            data.buffer.deinit();
            // data.file.deinit(); // Doesnt actually do anything but cause a compile error
        },
    }
}

pub fn sort(_: void, lhs: @This(), rhs: @This()) bool {
    return lhs.position < rhs.position;
}

pub fn run(self: *@This()) !void {
    self.process = std.ChildProcess.init(self.args, self.alloc);
    self.process.?.stdin_behavior = .Ignore;
    self.process.?.stdout_behavior = .Pipe;
    self.process.?.stderr_behavior = .Ignore;
    try self.process.?.spawn();
    switch (self.data) {
        .once => |*data| {
            data.process = try xev.Process.init(self.process.?.id);
            data.process.wait(self.loop, &self.completion, @This(), self, onceCallback);
        },
        .interval => |*data| {
            data.process = try xev.Process.init(self.process.?.id);
            data.process.wait(self.loop, &self.completion, @This(), self, firstIntervalCallback);
        },
        .live => |*data| {
            data.file = try xev.File.init(self.process.?.stdout.?);
            data.file.pread(self.loop, &self.completion, .{ .array = std.mem.zeroes([32]u8) }, 0, @This(), self, liveCallback);
        },
    }
}

fn calcWidth(content: []const u8) !usize {
    var width: usize = 0;
    var last_pos: usize = 0;
    while (std.mem.indexOfScalarPos(u8, content, last_pos, '%')) |new_pos| {
        width += try std.unicode.utf8CountCodepoints(content[last_pos..new_pos]);
        switch (content[new_pos + 1]) {
            '{' => if (std.mem.indexOfScalarPos(u8, content, new_pos + 1, '}')) |end| {
                last_pos = end + 1;
            } else return error.MalformedEscape,
            '%' => {
                width += 1;
                last_pos = new_pos + 2;
            },
            else => {
                width += 1;
                last_pos = new_pos + 1;
            },
        }
    } else width += try std.unicode.utf8CountCodepoints(content[last_pos..]);
    return width;
}

fn update(self: *@This(), new_content: []const u8) !void {
    defer self.alloc.free(new_content);
    const width = try calcWidth(new_content);

    const padded_len = new_content.len + if (width > self.min_width) 0 else self.min_width - width;
    const index = switch (self.fill_direction) {
        .left => 0,
        .center => (padded_len - new_content.len) / 2,
        .right => padded_len - new_content.len,
    };
    const padded = try self.alloc.alloc(u8, padded_len);
    @memset(padded, ' ');
    @memcpy(padded[index .. index + new_content.len], new_content);

    if (self.content) |content| self.alloc.free(content);
    self.content = padded;
    try self.bar.update();
}

fn readStdout(self: *@This()) !void {
    var reader = std.io.bufferedReader(self.process.?.stdout.?.reader());
    var array = std.ArrayList(u8).init(self.alloc);
    try reader.reader().streamUntilDelimiter(array.writer(), '\n', null);
    try self.update(try array.toOwnedSlice());
}

fn cancelCallback(
    _: ?*void,
    _: *xev.Loop,
    _: *xev.Completion,
    result: xev.CancelError!void,
) xev.CallbackAction {
    _ = result catch unreachable;
    return .disarm;
}

fn onceCallback(
    userdata: ?*@This(),
    _: *xev.Loop,
    _: *xev.Completion,
    result: xev.Process.WaitError!u32,
) xev.CallbackAction {
    _ = result catch unreachable;
    const self = userdata.?;
    self.readStdout() catch unreachable;
    self.process = null;
    return .disarm;
}

fn firstIntervalCallback(
    userdata: ?*@This(),
    loop: *xev.Loop,
    completion: *xev.Completion,
    result: xev.Process.WaitError!u32,
) xev.CallbackAction {
    _ = result catch unreachable;
    const self = userdata.?;
    self.readStdout() catch unreachable;
    self.process = std.ChildProcess.init(self.args, self.alloc);
    self.process.?.stdout_behavior = .Pipe;
    self.process.?.spawn() catch unreachable;
    self.data.interval.timer.run(loop, completion, self.data.interval.interval, @This(), self, intervalCallback);
    return .disarm;
}

fn intervalCallback(
    userdata: ?*@This(),
    loop: *xev.Loop,
    completion: *xev.Completion,
    result: xev.Timer.RunError!void,
) xev.CallbackAction {
    result catch unreachable;
    const self = userdata.?;
    self.readStdout() catch unreachable;
    _ = self.process.?.wait() catch unreachable;
    self.process = std.ChildProcess.init(self.args, self.alloc);
    self.process.?.stdout_behavior = .Pipe;
    self.process.?.spawn() catch unreachable;
    self.data.interval.timer.run(loop, completion, self.data.interval.interval, @This(), self, intervalCallback);
    return .disarm;
}

fn liveCallback(
    userdata: ?*@This(),
    _: *xev.Loop,
    _: *xev.Completion,
    _: xev.File,
    buf: xev.ReadBuffer,
    result: xev.File.ReadError!usize,
) xev.CallbackAction {
    const len = result catch unreachable;
    const self = userdata.?;
    var data = buf.array[0..len];
    while (std.mem.indexOfScalar(u8, data, '\n')) |i| {
        self.data.live.buffer.appendSlice(data[0..i]) catch unreachable;
        self.update(self.data.live.buffer.toOwnedSlice() catch unreachable) catch unreachable;
        self.data.live.buffer = std.ArrayList(u8).init(self.alloc);
        data = data[i + 1 ..];
    }
    self.data.live.buffer.appendSlice(data) catch unreachable;
    return .rearm;
}
