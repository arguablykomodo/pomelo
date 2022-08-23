const std = @import("std");
const Bar = @import("Bar.zig");

pub fn main() anyerror!void {
    var bar = try Bar.init(std.heap.c_allocator);
    defer bar.deinit();

    try bar.start();
}

test {
    _ = @import("ini.zig");
    _ = @import("wordexp.zig");
}
