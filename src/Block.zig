const std = @import("std");
const parse = @import("ini.zig").parse;
const wordexp = @import("wordexp.zig");
const Bar = @import("Bar.zig");

const Self = @This();

allocator: std.mem.Allocator,
expansion: wordexp.wordexp_t,
args: []const []const u8,
mode: Mode,
interval: ?usize = null,
side: Side,
position: usize = 0,
prefix: std.ArrayList(u8),
content: []const u8,
postfix: std.ArrayList(u8),

const Mode = enum { once, interval, live };
const Side = enum { left, center, right };

const Config = struct {
    command: []const u8 = "",
    mode: []const u8 = "",
    interval: ?usize = null,
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

pub fn init(alloc: std.mem.Allocator, dir: *std.fs.Dir, filename: []const u8, defaults: *Bar.Defaults) !Self {
    var self: Self = undefined;
    self.allocator = alloc;
    const config_bytes = try dir.readFileAlloc(self.allocator, filename, 1024 * 5);
    defer self.allocator.free(config_bytes);
    var config = try parse(Config, config_bytes);

    if (std.mem.eql(u8, config.command, "")) return error.MissingCommand;

    const terminated = try std.mem.concat(self.allocator, u8, &.{ config.command, "\x00" });
    defer self.allocator.free(terminated);
    self.expansion = try wordexp.wordexp(@ptrCast([*c]const u8, terminated));

    const casted = std.mem.span(@ptrCast([*:null]?[*:0]const u8, self.expansion.we_wordv));
    var args = try self.allocator.alloc([]const u8, casted.len);
    for (casted) |arg, i| {
        args[i] = std.mem.span(arg.?);
    }
    self.args = args;

    if (std.mem.eql(u8, config.mode, "once")) {
        self.mode = .once;
    } else if (std.mem.eql(u8, config.mode, "interval")) {
        self.mode = .interval;
    } else if (std.mem.eql(u8, config.mode, "live")) {
        self.mode = .live;
    } else return error.UnknownBlockMode;

    if (std.mem.eql(u8, config.side, "left")) {
        self.side = .left;
    } else if (std.mem.eql(u8, config.side, "center")) {
        self.side = .center;
    } else if (std.mem.eql(u8, config.side, "right")) {
        self.side = .right;
    } else return error.UnknownBlockSide;

    if (self.mode == .interval and config.interval == null) return error.MissingInterval;

    if (config.margin_left == null) config.margin_left = defaults.*.margin_left;
    if (config.margin_right == null) config.margin_right = defaults.*.margin_right;
    if (config.padding == null) config.padding = defaults.*.padding;
    if (config.underline == null) config.underline = defaults.*.underline;
    if (config.overline == null) config.overline = defaults.*.overline;
    if (config.background_color == null) config.background_color = defaults.*.background_color;

    self.prefix = std.ArrayList(u8).init(self.allocator);
    var prefix = self.prefix.writer();
    if (config.margin_left) |o| try prefix.print("%{{O{s}}}", .{o});
    if (config.left_click) |a| try prefix.print("%{{A1:{s}:}}", .{a});
    if (config.middle_click) |a| try prefix.print("%{{A2:{s}:}}", .{a});
    if (config.right_click) |a| try prefix.print("%{{A3:{s}:}}", .{a});
    if (config.scroll_up) |a| try prefix.print("%{{A4:{s}:}}", .{a});
    if (config.scroll_down) |a| try prefix.print("%{{A5:{s}:}}", .{a});
    if (config.background_color) |b| try prefix.print("%{{B{s}}}", .{b});
    if (config.foreground_color) |f| try prefix.print("%{{F{s}}}", .{f});
    if (config.line_color) |u| try prefix.print("%{{U{s}}}", .{u});
    if (config.underline.?) try prefix.writeAll("%{+u}");
    if (config.overline.?) try prefix.writeAll("%{+o}");
    if (config.padding) |o| try prefix.print("%{{O{s}}}", .{o});

    self.content = "";

    self.postfix = std.ArrayList(u8).init(self.allocator);
    var postfix = self.postfix.writer();
    if (config.padding) |o| try postfix.print("%{{O{s}}}", .{o});
    if (config.overline.?) try postfix.writeAll("%{-o}");
    if (config.underline.?) try postfix.writeAll("%{-u}");
    if (config.line_color) |_| try postfix.writeAll("%{U-}");
    if (config.foreground_color) |_| try postfix.writeAll("%{F-}");
    if (config.background_color) |_| try postfix.writeAll("%{B-}");
    if (config.scroll_down) |_| try postfix.writeAll("%{A}");
    if (config.scroll_up) |_| try postfix.writeAll("%{A}");
    if (config.right_click) |_| try postfix.writeAll("%{A}");
    if (config.middle_click) |_| try postfix.writeAll("%{A}");
    if (config.left_click) |_| try postfix.writeAll("%{A}");
    if (config.margin_right) |o| try postfix.print("%{{O{s}}}", .{o});

    return self;
}

pub fn start(self: *Self) !void {
    switch (self.mode) {
        .once => {
            var process = std.ChildProcess.init(self.args, self.allocator);
            process.stdin_behavior = .Ignore;
            process.stdout_behavior = .Pipe;
            process.stderr_behavior = .Inherit;
            try process.spawn();
            const stdout = process.stdout.?.reader();
            self.content = (try stdout.readUntilDelimiterOrEofAlloc(self.allocator, '\n', 1024)) orelse "";
            _ = try process.wait(); // TODO: inspect exit condition

        },
        .interval => return error.Unimplemented,
        .live => return error.Unimplemented,
    }
}

pub fn deinit(self: *Self) void {
    self.allocator.free(self.args);
    wordexp.wordfree(&self.expansion);
    self.prefix.deinit();
    self.postfix.deinit();
    self.allocator.free(self.content);
}
