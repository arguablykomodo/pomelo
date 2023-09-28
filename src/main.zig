const std = @import("std");
const xev = @import("xev");
const Bar = @import("Bar.zig");
const wordexp = @import("wordexp.zig");

pub fn main() anyerror!void {
    var config_dir = x: {
        var path = try wordexp.wordexp("${XDG_CONFIG_DIR:-$HOME/.config}/pomelo");
        defer wordexp.wordfree(&path);
        break :x try std.fs.openDirAbsolute(std.mem.span(path.we_wordv[0]), .{});
    };
    defer config_dir.close();

    var thread_pool = xev.ThreadPool.init(.{});
    var loop = try xev.Loop.init(.{ .thread_pool = &thread_pool });

    var bar = try Bar.init(std.heap.c_allocator, config_dir, &loop);
    defer bar.deinit();
    try bar.run();

    try loop.run(.until_done);
}

test {
    _ = @import("ini.zig");
    _ = @import("wordexp.zig");
}
