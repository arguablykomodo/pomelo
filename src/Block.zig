const std = @import("std");
const parse = @import("ini.zig").parse;
const wordexp = @import("wordexp.zig");
const Bar = @import("Bar.zig");

const Self = @This();

allocator: std.mem.Allocator,
config_bytes: []const u8,
config: Config,
expansion: wordexp.wordexp_t,
args: []const []const u8,
type: Type,
side: Side,
prefix: std.ArrayList(u8),
content: []const u8,
postfix: std.ArrayList(u8),

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

const Type = enum { once, interval, live };
const Side = enum { left, center, right };

pub fn init(alloc: std.mem.Allocator, dir: *std.fs.Dir, filename: []const u8, defaults: *Bar.Defaults) !Self {
    var self: Self = undefined;
    self.allocator = alloc;
    self.config_bytes = try dir.readFileAlloc(self.allocator, filename, 1024 * 5);
    self.config = try parse(Config, self.config_bytes);

    if (std.mem.eql(u8, self.config.command, "")) return error.MissingCommand;

    const terminated = try std.mem.concat(self.allocator, u8, &.{ self.config.command, "\x00" });
    defer self.allocator.free(terminated);
    self.expansion = try wordexp.wordexp(@ptrCast([*c]const u8, terminated));

    const casted = std.mem.span(@ptrCast([*:null]?[*:0]const u8, self.expansion.we_wordv));
    var args = try self.allocator.alloc([]const u8, casted.len);
    for (casted) |arg, i| {
        args[i] = std.mem.span(arg.?);
    }
    self.args = args;

    if (std.mem.eql(u8, self.config.type, "once")) {
        self.type = .once;
    } else if (std.mem.eql(u8, self.config.type, "interval")) {
        self.type = .interval;
    } else if (std.mem.eql(u8, self.config.type, "live")) {
        self.type = .live;
    } else return error.UnknownBlockType;

    if (std.mem.eql(u8, self.config.side, "left")) {
        self.side = .left;
    } else if (std.mem.eql(u8, self.config.side, "center")) {
        self.side = .center;
    } else if (std.mem.eql(u8, self.config.side, "right")) {
        self.side = .right;
    } else return error.UnknownBlockSide;

    if (self.type == .interval and self.config.interval == null) return error.MissingInterval;

    if (self.config.margin_left == null) self.config.margin_left = defaults.*.margin_left;
    if (self.config.margin_right == null) self.config.margin_right = defaults.*.margin_right;
    if (self.config.padding == null) self.config.padding = defaults.*.padding;
    if (self.config.underline == null) self.config.underline = defaults.*.underline;
    if (self.config.overline == null) self.config.overline = defaults.*.overline;
    if (self.config.background_color == null) self.config.background_color = defaults.*.background_color;

    self.prefix = std.ArrayList(u8).init(self.allocator);
    var prefix = self.prefix.writer();
    if (self.config.margin_left) |o| try prefix.print("%{{O{}}}", .{o});
    if (self.config.left_click) |a| try prefix.print("%{{A1:{s}:}}", .{a});
    if (self.config.middle_click) |a| try prefix.print("%{{A2:{s}:}}", .{a});
    if (self.config.right_click) |a| try prefix.print("%{{A3:{s}:}}", .{a});
    if (self.config.scroll_up) |a| try prefix.print("%{{A4:{s}:}}", .{a});
    if (self.config.scroll_down) |a| try prefix.print("%{{A5:{s}:}}", .{a});
    if (self.config.background_color) |b| try prefix.print("%{{B{s}}}", .{b});
    if (self.config.foreground_color) |f| try prefix.print("%{{F{s}}}", .{f});
    if (self.config.line_color) |u| try prefix.print("%{{U{s}}}", .{u});
    if (self.config.underline.?) try prefix.writeAll("%{+u}");
    if (self.config.overline.?) try prefix.writeAll("%{+o}");
    if (self.config.padding) |o| try prefix.print("%{{O{}}}", .{o});

    self.content = "";

    self.postfix = std.ArrayList(u8).init(self.allocator);
    var postfix = self.postfix.writer();
    if (self.config.padding) |o| try postfix.print("%{{O{}}}", .{o});
    if (self.config.overline.?) try postfix.writeAll("%{-o}");
    if (self.config.underline.?) try postfix.writeAll("%{-u}");
    if (self.config.line_color) |_| try postfix.writeAll("%{U-}");
    if (self.config.foreground_color) |_| try postfix.writeAll("%{F-}");
    if (self.config.background_color) |_| try postfix.writeAll("%{B-}");
    if (self.config.scroll_down) |_| try postfix.writeAll("%{A}");
    if (self.config.scroll_up) |_| try postfix.writeAll("%{A}");
    if (self.config.right_click) |_| try postfix.writeAll("%{A}");
    if (self.config.middle_click) |_| try postfix.writeAll("%{A}");
    if (self.config.left_click) |_| try postfix.writeAll("%{A}");
    if (self.config.margin_right) |o| try postfix.print("%{{O{}}}", .{o});

    return self;
}

pub fn start(self: *Self) !void {
    switch (self.type) {
        .once => {
            const process = try std.ChildProcess.init(self.args, self.allocator);
            process.stdin_behavior = .Ignore;
            process.stdout_behavior = .Pipe;
            process.stderr_behavior = .Inherit;
            defer process.deinit();
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
    self.allocator.free(self.config_bytes);
    self.prefix.deinit();
    self.postfix.deinit();
    self.allocator.free(self.content);
}
