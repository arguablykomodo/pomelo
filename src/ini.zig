const std = @import("std");

pub fn parse(comptime T: type, bytes: []const u8) !T {
    const fields = @typeInfo(T).Struct.fields;

    var parsed: T = .{};
    var lines = std.mem.tokenize(u8, bytes, "\r\n");

    while (lines.next()) |line| {
        const trimmed = std.mem.trimLeft(u8, line, &std.ascii.spaces);
        switch (trimmed[0]) {
            ';' => continue,
            '[' => {
                const end = std.mem.indexOfScalar(u8, trimmed, ']') orelse return error.MissingSectionClose;
                const section = trimmed[1..end];
                inline for (fields) |field| {
                    switch (@typeInfo(field.field_type)) {
                        .Optional => |opt| if (@typeInfo(opt.child) != .Struct) continue,
                        .Struct => {},
                        else => continue,
                    }
                    if (std.mem.eql(u8, field.name, section)) {
                        @field(parsed, field.name) = try parse(field.field_type, lines.rest());
                        return parsed; // No support for multiple sections.
                    }
                } else return error.UnknownSection;
            },
            else => {
                const separator = std.mem.indexOfScalar(u8, trimmed, '=') orelse return error.MissingEquals;
                const key = std.mem.trim(u8, trimmed[0..separator], &std.ascii.spaces);
                const value = std.mem.trim(u8, trimmed[separator + 1 ..], &std.ascii.spaces);
                inline for (fields) |field| {
                    if (std.mem.eql(u8, field.name, key)) {
                        @field(parsed, field.name) = try parseValue(field.field_type, value);
                        break;
                    }
                } else return error.UnknownField;
            },
        }
    }
    return parsed;
}

fn parseValue(comptime T: type, bytes: []const u8) !T {
    switch (@typeInfo(T)) {
        .Int => return try std.fmt.parseInt(T, bytes, 0),
        .Bool => if (std.mem.eql(u8, bytes, "true")) {
            return true;
        } else if (std.mem.eql(u8, bytes, "false")) {
            return false;
        } else return error.MalformedBoolean,
        .Pointer => {
            if (T != []const u8) return error.Unimplemented;
            return bytes;
        },
        .Optional => |opt| return try parseValue(opt.child, bytes),
        else => return error.Unimplemented,
    }
}
