const c = @cImport({
    @cInclude("wordexp.h");
});

pub const wordexp_t = c.wordexp_t;

pub fn wordexp(string: [*c]const u8) !c.wordexp_t {
    var result: c.wordexp_t = undefined;
    switch (c.wordexp(string, &result, 0)) {
        0 => {},
        c.WRDE_BADCHAR => return error.IllegalCharacter,
        c.WRDE_BADVAL => return error.UndefinedShellVariable,
        c.WRDE_CMDSUB => return error.IllegalCommandSubstitution,
        c.WRDE_NOSPACE => return error.OutOfMemory,
        c.WRDE_SYNTAX => return error.SyntaxError,
        else => unreachable,
    }
    return result;
}

pub fn wordfree(result: *c.wordexp_t) void {
    c.wordfree(result);
}
