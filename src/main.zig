const std = @import("std");
const Bar = @import("Bar.zig");

pub fn main() anyerror!void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var bar = try Bar.init(allocator);
    defer bar.deinit();
}
