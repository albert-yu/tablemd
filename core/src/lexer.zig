const std = @import("std");
const re = @import("regex.zig");

/// Reference: https://support.microsoft.com/en-us/office/calculation-operators-and-precedence-in-excel-48be406d-4975-4d31-b2b8-7af9e0e2878a
const TokenType = enum {
    unknown,
    plus,
    minus,
    mult,
    div,
    percent,
    pow,
    l_paren,
    l_bracket,
    l_brace,
    r_paren,
    r_bracket,
    r_brace,
    arg_sep,
    row_sep,
    eq,
    lt,
    gt,
    lte,
    gte,
    neq,
    concat,
    range_op,
    space,
    pound,
    ref_op,
    cell_range_op,
    sheet_ref_op,
    ellipsis,
    false,
    true,
    comment,
    unterminated_block_comment,
    function_call,
    unquoted_sheet_ref,
    str_literal,
    unterminated_str_literal,
    num_literal,
    cell_ref,
    eof,
};

// longer patterns first
const PATTERNS = [_][]const u8{
    "false",
    "true",
    // !=, <=, >= comparison operators
    "[!<>]=",
    // equals (=) comparison operator
    "=",
};

fn joinStrings(strings: []const []const u8, sep: []const u8) []const u8 {
    comptime {
        var length: usize = 0;
        for (strings) |s| {
            length += s.len;
            length += sep.len;
        }

        var result: [length]u8 = undefined;
        var cursor: usize = 0;
        for (strings, 0..) |s, i| {
            std.mem.copy(u8, result[cursor..][0..s.len], s);
            cursor += s.len;
            if (i < strings.len - 1) {
                std.mem.copy(u8, result[cursor..][0..sep.len], sep);
                cursor += sep.len;
            }
        }

        return result[0..];
    }
}

const BASIC_TOKEN_REGEX = joinStrings(&PATTERNS, "|");

const Token = struct {
    type: TokenType,
    start: usize,
    end: usize,
};

const token_lookup = std.ComptimeStringMap(TokenType, .{
    .{ "+", .plus },
    .{ "-", .minus },
    .{ "*", .mult },
    .{ "/", .div },
    .{ "^", .pow },
    .{ "(", .l_paren },
    .{ "[", .l_bracket },
    .{ "{", .l_brace },
    .{ ")", .r_paren },
    .{ "]", .r_bracket },
    .{ "}", .r_brace },
    .{ ",", .arg_sep },
    .{ ";", .row_sep },
    .{ "=", .eq },
    .{ "<", .lt },
    .{ ">", .gt },
    .{ "<=", .lte },
    .{ ">=", .gte },
    .{ "<>", .neq },
    .{ "&", .concat },
    .{ ":", .range_op },
    .{ " ", .space },
    .{ "#", .pound },
    .{ "@", .ref_op },
    .{ "%", .percent },
    .{ "false", .false },
    .{ "FALSE", .false }, // of course, doesn't handle fAlSe or similar
    .{ "true", .true },
    .{ "TRUE", .true },
});

pub const Tokenizer = struct {
    input: []const u8,
    index: u64,
    regex: re.Regex,
    const Self = @This();

    pub fn new(allocator: std.mem.Allocator, s: []const u8) !Self {
        const regex = try re.Regex.new(allocator, BASIC_TOKEN_REGEX);
        return Self{
            .input = s,
            .index = 0,
            .regex = regex,
        };
    }

    pub fn destroy(self: *Self, allocator: std.mem.Allocator) void {
        self.regex.destroy(allocator);
    }

    pub fn next(self: *Self) !Token {
        if (self.index >= self.input.len) {
            return Token{
                .type = TokenType.eof,
                .start = self.index,
                .end = self.index,
            };
        }
        const str = self.input[self.index..];
        const maybe_match = self.regex.findFirst(str);
        if (maybe_match) |match| {
            const c = str[match.start..match.end];
            const tokenType = token_lookup.get(c) orelse TokenType.unknown;
            self.index += match.end;
            return Token{
                .type = tokenType,
                // need to adjust for initial offset
                .start = self.index + match.start,
                .end = self.index + match.end,
            };
        }
        return Token{
            .type = TokenType.eof,
            .start = self.index,
            .end = self.index,
        };
    }
};

test "lexer test" {
    const allocator = std.testing.allocator;
    var tokenizer = try Tokenizer.new(allocator, "false=TRUE");
    defer tokenizer.destroy(allocator);
    var token = try tokenizer.next();
    try std.testing.expectEqual(TokenType.false, token.type);
    token = try tokenizer.next();
    try std.testing.expectEqual(TokenType.eq, token.type);
    token = try tokenizer.next();
    try std.testing.expectEqual(TokenType.true, token.type);
}
