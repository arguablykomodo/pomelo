const std = @import("std");

const ParseError = error{
    MissingSectionClose,
    UnknownSection,
    MissingEquals,
    UnknownField,
    UnsetMandatoryField,
} || ParseValueError;

pub fn parse(comptime T: type, bytes: []const u8) ParseError!T {
    const fields = @typeInfo(T).Struct.fields;

    const mandatory_fields = blk: {
        comptime var mandatory_fields = 0;
        inline for (fields) |field| {
            if (@typeInfo(field.type) != .Optional and
                field.default_value == null) mandatory_fields += 1;
        }
        break :blk mandatory_fields;
    };
    var set_fields: usize = 0;

    var parsed = std.mem.zeroInit(T, .{});
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
                        if (@typeInfo(field.type) != .Optional and
                            field.default_value == null) set_fields += 1;
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
                        if (@typeInfo(field.type) != .Optional and
                            field.default_value == null) set_fields += 1;
                        break;
                    }
                } else return ParseError.UnknownField;
            },
        }
    }

    if (set_fields < mandatory_fields) return ParseError.UnsetMandatoryField;
    return parsed;
}

const ParseValueError = error{
    MalformedBoolean,
    Unimplemented,
    UnknownEnumVariant,
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
        .Enum => |@"enum"| {
            inline for (@"enum".fields) |field| {
                if (std.mem.eql(u8, bytes, field.name)) {
                    return @field(T, field.name);
                }
            }
            return ParseValueError.UnknownEnumVariant;
        },
        else => return ParseValueError.Unimplemented,
    }
}

test "parse" {
    const Struct = struct {
        foo: u64 = 0,
        bar: struct { baz: u64 = 0 } = .{},
        qux: u8,
    };
    try std.testing.expectEqual(Struct{ .foo = 10, .qux = 0 }, try parse(Struct,
        \\foo = 10
        \\qux = 0
    ));
    try std.testing.expectEqual(Struct{ .foo = 10, .qux = 0 }, try parse(Struct,
        \\; This is a comment
        \\foo = 10
        \\qux = 0
    ));
    try std.testing.expectEqual(Struct{ .foo = 10, .bar = .{ .baz = 10 }, .qux = 0 }, try parse(Struct,
        \\foo = 10
        \\qux = 0
        \\[bar]
        \\baz = 10
    ));
    try std.testing.expectError(ParseError.MissingSectionClose, parse(Struct, "[what"));
    try std.testing.expectError(ParseError.UnknownField, parse(Struct, "baz = 10"));
    try std.testing.expectError(ParseError.UnknownSection, parse(Struct,
        \\qux = 0
        \\[what]
        \\bar = 10
    ));
    try std.testing.expectError(ParseError.UnsetMandatoryField, parse(Struct, "foo = 10"));
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

    const Enum = enum { foo, bar };
    try std.testing.expectEqual(Enum.foo, try parseValue(Enum, "foo"));
    try std.testing.expectEqual(Enum.bar, try parseValue(Enum, "bar"));
    try std.testing.expectError(ParseValueError.UnknownEnumVariant, parseValue(Enum, "baz"));

    try std.testing.expectError(ParseValueError.Unimplemented, parseValue(f32, "5.0"));
}
