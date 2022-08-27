const std = @import("std");
const Bar = @import("Bar.zig");
const wordexp = @import("wordexp.zig");

pub fn main() anyerror!void {
    var config_dir = x: {
        const path = try wordexp.wordexp("${XDG_CONFIG_DIR:-$HOME/.config}/pomelo");
        defer wordexp.wordfree(&path);
        break :x try std.fs.openDirAbsolute(std.mem.span(path.we_wordv[0]), .{});
    };
    defer config_dir.close();

    var bar = try Bar.init(config_dir, std.heap.c_allocator);
    defer bar.deinit();

    try bar.start();
}

test {
    _ = @import("ini.zig");
    _ = @import("wordexp.zig");
    _ = @import("Block.zig");
    _ = @import("Bar.zig");
}
