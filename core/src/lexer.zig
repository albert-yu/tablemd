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
    // ellipsis,
    false,
    true,
    // comment,
    // unterminated_block_comment,
    function_call,
    // unquoted_sheet_ref,
    str_literal,
    // unterminated_str_literal,
    num_literal,
    cell_ref,
    eof,
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

fn comptimeMergeStringArrays(comptime arrays: anytype) []const []const u8 {
    comptime {
        // Calculate total length first
        var totalLength: usize = 0;
        for (arrays) |array| {
            totalLength += array.len;
        }

        // Allocate space for the merged array
        var merged: [totalLength][]const u8 = undefined;

        // Merge arrays
        var index: usize = 0;
        for (arrays) |array| {
            for (array) |str| {
                merged[index] = str;
                index += 1;
            }
        }
        return merged[0..];
    }
}

/// Incomplete list of Excel functions
/// Source: https://support.microsoft.com/en-us/office/excel-functions-alphabetical-b3944572-255d-4efb-bb96-c6d90033e188
const FUNCTIONS = [_][]const u8{
    "ABS",
    "AND",
    "AVERAGE",
    "AVERAGEIF",
    "BASE",
    "OR",
    "PRODUCT",
    "SORT",
    "SORTBY",
    "SQRT",
    "SQRTPI",
    "SUM",
    "SUMIF",
    "XOR",
};

const OPERATORS = [_][]const u8{
    ">=",
    "<=",
    "<",
    ">",
    "<>",
    "=",
    "\\+",
    "\\-",
    "\\*",
    "\\/",
    "\\^",
    "&",
    "%",
    "#",
};

const CELL_REFS = [_][]const u8{
    "\\$?[a-zA-Z]{1,2}\\$?[0-9]+",
};

const SYMBOLS = [_][]const u8{
    "\\(",
    "\\)",
    "\\{",
    "\\}",
    "\\[",
    "\\]",
    "\\,",
    ";",
    "\"",
};

const NUM_LITERALS = [_][]const u8{
    // number
    "[0-9]+",
};

const STR_LITERALS = [_][]const u8{
    // string enclosed in double quotes
    "\".*\"",
    // string with leading single quote
    "'.*",
};

const KEYWORDS = [_][]const u8{
    "false",
    "true",
};

const ALL_PATTERNS = comptimeMergeStringArrays([_][]const []const u8{
    &FUNCTIONS,
    &OPERATORS,
    &KEYWORDS,
    &SYMBOLS,
    &CELL_REFS,
    &NUM_LITERALS,
    &STR_LITERALS,
});

const ALL_TOKENS_REGEX = joinStrings(ALL_PATTERNS, "|");
const CELL_REF_REGEX = joinStrings(&CELL_REFS, "|");
const NUM_LITERALS_REGEX = joinStrings(&NUM_LITERALS, "|");
const STR_LITERALS_REGEX = joinStrings(&STR_LITERALS, "|");

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
    regex_all_tokens: re.Regex,
    cell_ref_regex: re.Regex,
    num_literal_regex: re.Regex,
    str_literal_regex: re.Regex,
    const Self = @This();

    pub fn new(allocator: std.mem.Allocator, s: []const u8) !Self {
        // TODO: make regex explicitly greedy, case-insensitive
        const regex = try re.Regex.new(allocator, ALL_TOKENS_REGEX);
        // std.debug.print("{s}\n", .{ALL_TOKENS_REGEX});
        const cell_ref_regex = try re.Regex.new(
            allocator,
            CELL_REF_REGEX,
        );
        const num_literal_regex = try re.Regex.new(
            allocator,
            NUM_LITERALS_REGEX,
        );
        const str_literal_regex = try re.Regex.new(
            allocator,
            STR_LITERALS_REGEX,
        );
        return Self{ .input = s, .index = 0, .regex_all_tokens = regex, .cell_ref_regex = cell_ref_regex, .num_literal_regex = num_literal_regex, .str_literal_regex = str_literal_regex };
    }

    pub fn destroy(self: *Self, allocator: std.mem.Allocator) void {
        self.regex_all_tokens.destroy(allocator);
        self.cell_ref_regex.destroy(allocator);
        self.num_literal_regex.destroy(allocator);
        self.str_literal_regex.destroy(allocator);
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
        const maybe_match = self.regex_all_tokens.findFirst(str);
        if (maybe_match) |match| {
            const c = str[match.start..match.end];
            const start = self.index + match.start;
            const end = self.index + match.end;
            // mutate AFTER reading start and end
            self.index += match.end;
            const tokenType = token_lookup.get(c);
            if (tokenType) |tok| {
                return Token{
                    .type = tok,
                    // need to adjust for initial offset
                    .start = start,
                    .end = end,
                };
            }
            // try regexps one by one
            const maybe_match_cell_ref = self.cell_ref_regex.findFirst(c);
            if (maybe_match_cell_ref) |matched_cell_ref| {
                _ = matched_cell_ref;
                return Token{
                    .type = .cell_ref,
                    .start = start,
                    .end = end,
                };
            }
            const maybe_num_lit = self.num_literal_regex.findFirst(c);
            if (maybe_num_lit) |num_lit| {
                _ = num_lit;
                return Token{
                    .type = .num_literal,
                    .start = start,
                    .end = end,
                };
            }
        }
        return error.UnexpectedCharacter;
    }
};

test "lexer test" {
    const allocator = std.testing.allocator;

    const basic_cell_ref = "$A3=TRUE";
    var tokenizer_basic_cell_ref = try Tokenizer.new(allocator, basic_cell_ref);
    defer tokenizer_basic_cell_ref.destroy(allocator);

    var token = try tokenizer_basic_cell_ref.next();
    const str_1 = basic_cell_ref[token.start..token.end];
    try std.testing.expectEqualStrings("$A3", str_1);
    try std.testing.expectEqual(TokenType.cell_ref, token.type);
    token = try tokenizer_basic_cell_ref.next();
    const str_2 = basic_cell_ref[token.start..token.end];
    try std.testing.expectEqualStrings("=", str_2);
    try std.testing.expectEqual(TokenType.eq, token.type);
    token = try tokenizer_basic_cell_ref.next();
    const str_3 = basic_cell_ref[token.start..token.end];
    try std.testing.expectEqualStrings("TRUE", str_3);
    try std.testing.expectEqual(TokenType.true, token.type);

    const basic_arith = "4+5";
    var tokenizer_basic_arith = try Tokenizer.new(allocator, basic_arith);
    defer tokenizer_basic_arith.destroy(allocator);

    token = try tokenizer_basic_arith.next();
    try std.testing.expectEqualStrings("4", basic_arith[token.start..token.end]);
    try std.testing.expectEqual(TokenType.num_literal, token.type);
    token = try tokenizer_basic_arith.next();
    try std.testing.expectEqualStrings("+", basic_arith[token.start..token.end]);
    try std.testing.expectEqual(TokenType.plus, token.type);
    token = try tokenizer_basic_arith.next();
    try std.testing.expectEqualStrings("5", basic_arith[token.start..token.end]);
    try std.testing.expectEqual(TokenType.num_literal, token.type);
}
