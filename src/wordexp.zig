const std = @import("std");
const c = @cImport({
    @cInclude("wordexp.h");
});

pub const wordexp_t = c.wordexp_t;

const WordexpError = error{
    IllegalCharacter,
    OutOfMemory,
    SyntaxError,
};

pub fn wordexp(string: [*c]const u8) WordexpError!c.wordexp_t {
    var result: c.wordexp_t = undefined;
    switch (c.wordexp(string, &result, 0)) {
        0 => {},
        c.WRDE_BADCHAR => return WordexpError.IllegalCharacter,
        c.WRDE_NOSPACE => return WordexpError.OutOfMemory,
        c.WRDE_SYNTAX => return WordexpError.SyntaxError,
        else => unreachable,
    }
    return result;
}

pub fn wordfree(result: [*c]c.wordexp_t) void {
    c.wordfree(result);
}

test "wordexp" {
    var expansion = try wordexp("foo bar \"$(echo baz zug)\"");
    wordfree(&expansion);
    try std.testing.expectError(WordexpError.IllegalCharacter, wordexp("foo } bar"));
    try std.testing.expectError(WordexpError.SyntaxError, wordexp("\"foo"));
}
