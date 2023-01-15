const std = @import("std");

const ParseError = error{
    MissingSectionClose,
    UnknownSection,
    MissingEquals,
    UnknownField,
} || ParseValueError;

pub fn parse(comptime T: type, bytes: []const u8) ParseError!T {
    const fields = @typeInfo(T).Struct.fields;

    var parsed: T = .{};
    var lines = std.mem.tokenize(u8, bytes, "\r\n");

    while (lines.next()) |line| {
        const trimmed = std.mem.trimLeft(u8, line, &std.ascii.whitespace);
        switch (trimmed[0]) {
            ';' => continue,
            '[' => {
                const end = std.mem.indexOfScalar(u8, trimmed, ']') orelse return ParseError.MissingSectionClose;
                const section = trimmed[1..end];
                inline for (fields) |field| {
                    switch (@typeInfo(field.type)) {
                        .Optional => |opt| if (@typeInfo(opt.child) != .Struct) continue,
                        .Struct => {},
                        else => continue,
                    }
                    if (std.mem.eql(u8, field.name, section)) {
                        @field(parsed, field.name) = try parse(field.type, lines.rest());
                        return parsed; // No support for multiple sections.
                    }
                } else return ParseError.UnknownSection;
            },
            else => {
                const separator = std.mem.indexOfScalar(u8, trimmed, '=') orelse return ParseError.MissingEquals;
                const key = std.mem.trim(u8, trimmed[0..separator], &std.ascii.whitespace);
                const value = std.mem.trim(u8, trimmed[separator + 1 ..], &std.ascii.whitespace);
                inline for (fields) |field| {
                    if (std.mem.eql(u8, field.name, key)) {
                        @field(parsed, field.name) = try parseValue(field.type, value);
                        break;
                    }
                } else return ParseError.UnknownField;
            },
        }
    }
    return parsed;
}

const ParseValueError = error{
    MalformedBoolean,
    Unimplemented,
} || std.fmt.ParseIntError;

fn parseValue(comptime T: type, bytes: []const u8) ParseValueError!T {
    switch (@typeInfo(T)) {
        .Int => return try std.fmt.parseInt(T, bytes, 0),
        .Bool => if (std.mem.eql(u8, bytes, "true")) {
            return true;
        } else if (std.mem.eql(u8, bytes, "false")) {
            return false;
        } else return ParseValueError.MalformedBoolean,
        .Pointer => {
            if (T != []const u8) return ParseValueError.Unimplemented;
            return bytes;
        },
        .Optional => |opt| return try parseValue(opt.child, bytes),
        else => return ParseValueError.Unimplemented,
    }
}

test "parse" {
    const Struct = struct {
        foo: u64 = 0,
        bar: struct { baz: u64 = 0 } = .{},
    };
    try std.testing.expectEqual(Struct{ .foo = 10 }, try parse(Struct, "foo = 10"));
    try std.testing.expectEqual(Struct{ .foo = 10 }, try parse(Struct,
        \\; This is a comment
        \\foo = 10
    ));
    try std.testing.expectEqual(Struct{ .foo = 10, .bar = .{ .baz = 10 } }, try parse(Struct,
        \\foo = 10
        \\[bar]
        \\baz = 10
    ));
    try std.testing.expectError(ParseError.MissingSectionClose, parse(Struct, "[what"));
    try std.testing.expectError(ParseError.UnknownField, parse(Struct, "baz = 10"));
    try std.testing.expectError(ParseError.UnknownSection, parse(Struct,
        \\[what]
        \\bar = 10
    ));
}

test "parseValue" {
    try std.testing.expectEqual(@as(u64, 10), try parseValue(u64, "10"));
    try std.testing.expectEqual(@as(u64, 10), try parseValue(u64, "0xA"));
    try std.testing.expectEqual(@as(u64, 10), try parseValue(u64, "0o12"));
    try std.testing.expectEqual(@as(u64, 10), try parseValue(u64, "0b1010"));

    try std.testing.expectEqual(false, try parseValue(bool, "false"));
    try std.testing.expectEqual(true, try parseValue(bool, "true"));
    try std.testing.expectError(ParseValueError.MalformedBoolean, parseValue(bool, "foo"));

    try std.testing.expectEqualStrings("foo", try parseValue([]const u8, "foo"));
    try std.testing.expectEqualStrings("\"bar\"", try parseValue([]const u8, "\"bar\""));
    try std.testing.expectError(ParseValueError.Unimplemented, parseValue(*u64, "foo"));

    try std.testing.expectEqual(@as(?bool, false), try parseValue(?bool, "false"));
    try std.testing.expectEqual(@as(?bool, true), try parseValue(?bool, "true"));

    try std.testing.expectError(ParseValueError.Unimplemented, parseValue(f32, "5.0"));
}
