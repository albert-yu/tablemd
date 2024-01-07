const std = @import("std");
const re = @import("regex.zig");

/// Reference: https://support.microsoft.com/en-us/office/calculation-operators-and-precedence-in-excel-48be406d-4975-4d31-b2b8-7af9e0e2878a
pub const TokenType = enum {
    unknown,
    /// +
    plus,
    /// -
    minus,
    /// *
    mult,
    /// /
    div,
    /// %
    percent,
    /// ^
    pow,
    /// (
    l_paren,
    /// [
    l_bracket,
    /// {
    l_brace,
    /// )
    r_paren,
    /// ]
    r_bracket,
    /// }
    r_brace,
    /// ,
    arg_sep,
    /// ;
    row_sep,
    /// =
    eq,
    /// <
    lt,
    /// >
    gt,
    /// <=
    lte,
    /// >=
    gte,
    /// <>
    neq,
    /// &
    concat,
    /// :
    range_op,
    /// " " (without quotes, duh)
    space,
    /// #
    pound,
    /// @
    ref_op,
    /// FALSE (case-insensitive)
    false,
    /// TRUE (case-insensitive)
    true,
    /// FOO(...)
    func_call,
    str_literal,
    num_literal,
    /// A4, B12, Z99
    cell_ref,
    /// end of input
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

fn concatStringArrays(comptime arrays: anytype) []const []const u8 {
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
    "INDEX",
    "LEN",
    "LENB",
    "MAP",
    "MATCH",
    "NOT",
    "OR",
    "PRODUCT",
    "RAND",
    "SORT",
    "SORTBY",
    "SQRT",
    "SQRTPI",
    "SUM",
    "SUMIF",
    "VLOOKUP",
    "XOR",
};

/// TODO: read all this carefully:
/// https://support.microsoft.com/en-us/office/calculation-operators-and-precedence-in-excel-48be406d-4975-4d31-b2b8-7af9e0e2878a
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
    ":",
    "@",
};

/// TODO: support Sheet + Cell ref
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
    "[0-9]*\\.?[0-9]+",
};

const STR_LITERALS = [_][]const u8{
    // string enclosed in double quotes
    "\".*\"",
    // string with leading single quote
    "'.*",
};

const WHITESPACE = [_][]const u8{
    // TODO: consider [[:space:]]
    "[ ]+",
};

const KEYWORDS = [_][]const u8{
    "false",
    "true",
};

const ALL_PATTERNS = concatStringArrays([_][]const []const u8{
    &FUNCTIONS,
    &OPERATORS,
    &KEYWORDS,
    &SYMBOLS,
    &CELL_REFS,
    &NUM_LITERALS,
    &STR_LITERALS,
    &WHITESPACE,
});

const ALL_TOKENS_REGEX = joinStrings(ALL_PATTERNS, "|");
const CELL_REF_REGEX = joinStrings(&CELL_REFS, "|");
const NUM_LITERALS_REGEX = joinStrings(&NUM_LITERALS, "|");
const STR_LITERALS_REGEX = joinStrings(&STR_LITERALS, "|");
const WHITESPACE_REGEX = joinStrings(&WHITESPACE, "|");
const FUNCTION_REGEX = joinStrings(&FUNCTIONS, "|");

pub const Token = struct {
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
    regex_cell_ref: re.Regex,
    regex_num_lit: re.Regex,
    regex_str_lit: re.Regex,
    regex_whitespace: re.Regex,
    regex_func: re.Regex,
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
        const whitespace_regex = try re.Regex.new(allocator, WHITESPACE_REGEX);
        const func_regex = try re.Regex.new(allocator, FUNCTION_REGEX);
        return Self{
            .input = s,
            .index = 0,
            .regex_all_tokens = regex,
            .regex_cell_ref = cell_ref_regex,
            .regex_num_lit = num_literal_regex,
            .regex_str_lit = str_literal_regex,
            .regex_whitespace = whitespace_regex,
            .regex_func = func_regex,
        };
    }

    pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        self.regex_all_tokens.deinit(allocator);
        self.regex_cell_ref.deinit(allocator);
        self.regex_num_lit.deinit(allocator);
        self.regex_str_lit.deinit(allocator);
        self.regex_whitespace.deinit(allocator);
        self.regex_func.deinit(allocator);
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
        const maybe_match = self.regex_all_tokens.matchStart(str);
        if (maybe_match) |match| {
            const c = str[match.start..match.end];
            // need to adjust for initial offset
            const start = self.index + match.start;
            const end = self.index + match.end;
            // mutate AFTER reading start and end
            self.index += match.end;
            const token_type = token_lookup.get(c);
            if (token_type) |tok| {
                return Token{
                    .type = tok,
                    .start = start,
                    .end = end,
                };
            }
            // try regexps one by one
            const maybe_match_cell_ref = self.regex_cell_ref.matchStart(c);
            if (maybe_match_cell_ref) |matched_cell_ref| {
                _ = matched_cell_ref;
                return Token{
                    .type = .cell_ref,
                    .start = start,
                    .end = end,
                };
            }
            const maybe_num_lit = self.regex_num_lit.matchStart(c);
            if (maybe_num_lit) |num_lit| {
                _ = num_lit;
                return Token{
                    .type = .num_literal,
                    .start = start,
                    .end = end,
                };
            }
            const maybe_str_lit = self.regex_str_lit.matchStart(c);
            if (maybe_str_lit) |str_lit| {
                _ = str_lit;
                return Token{
                    .type = .str_literal,
                    .start = start,
                    .end = end,
                };
            }
            const maybe_whitespace = self.regex_whitespace.matchStart(c);
            if (maybe_whitespace) |ws| {
                _ = ws;
                return Token{
                    .type = .space,
                    .start = start,
                    .end = end,
                };
            }
            const match_func_call = self.regex_func.matchStart(c);
            if (match_func_call) |fc| {
                _ = fc;
                return Token{
                    .type = .func_call,
                    .start = start,
                    .end = end,
                };
            }
        }
        return error.UnexpectedCharacter;
    }
};

const ExpectedToken = struct {
    str: []const u8,
    type: TokenType,
};

fn testTokenizerInput(allocator: std.mem.Allocator, input: []const u8, expected: []const ExpectedToken) !void {
    var tokenizer = try Tokenizer.new(allocator, input);
    defer tokenizer.deinit(allocator);

    var token = try tokenizer.next();
    var i: usize = 0;
    while (token.type != .eof) {
        const expected_token = expected[i];
        try std.testing.expectEqualStrings(expected_token.str, input[token.start..token.end]);
        try std.testing.expectEqual(expected_token.type, token.type);
        i += 1;
        token = try tokenizer.next();
    }
}

test "lexer basic test" {
    const allocator = std.testing.allocator;

    const basic_cell_ref = "$A3=TRUE";
    try testTokenizerInput(allocator, basic_cell_ref, &[_]ExpectedToken{
        .{
            .str = "$A3",
            .type = .cell_ref,
        },
        .{
            .str = "=",
            .type = .eq,
        },
        .{
            .str = "TRUE",
            .type = .true,
        },
    });

    const basic_arith = "4+5";
    try testTokenizerInput(allocator, basic_arith, &[_]ExpectedToken{
        .{
            .str = "4",
            .type = .num_literal,
        },
        .{
            .str = "+",
            .type = .plus,
        },
        .{
            .str = "5",
            .type = .num_literal,
        },
    });

    const str_literal = "'=SUM(A4:A5)";
    try testTokenizerInput(allocator, str_literal, &[_]ExpectedToken{
        .{
            .str = "'=SUM(A4:A5)",
            .type = .str_literal,
        },
    });

    const with_whitespace = "$ZQ$8989 -   100";
    try testTokenizerInput(allocator, with_whitespace, &[_]ExpectedToken{
        .{
            .type = .cell_ref,
            .str = "$ZQ$8989",
        },
        .{
            .type = .space,
            .str = " ",
        },
        .{
            .type = .minus,
            .str = "-",
        },
        .{
            .type = .space,
            .str = "   ",
        },
        .{
            .type = .num_literal,
            .str = "100",
        },
    });

    const func_call = "SUM(B1:B40)";
    try testTokenizerInput(allocator, func_call, &[_]ExpectedToken{
        .{
            .type = .func_call,
            .str = "SUM",
        },
        .{
            .type = .l_paren,
            .str = "(",
        },
        .{
            .type = .cell_ref,
            .str = "B1",
        },
        .{
            .type = .range_op,
            .str = ":",
        },
        .{
            .type = .cell_ref,
            .str = "B40",
        },
        .{
            .type = .r_paren,
            .str = ")",
        },
    });

    const func_call_args = "PRODUCT($R$4,$R$5)";
    try testTokenizerInput(allocator, func_call_args, &[_]ExpectedToken{
        .{
            .type = .func_call,
            .str = "PRODUCT",
        },
        .{
            .type = .l_paren,
            .str = "(",
        },
        .{
            .type = .cell_ref,
            .str = "$R$4",
        },
        .{
            .type = .arg_sep,
            .str = ",",
        },
        .{
            .type = .cell_ref,
            .str = "$R$5",
        },
        .{
            .type = .r_paren,
            .str = ")",
        },
    });
}

test "bit more complicated" {
    const allocator = std.testing.allocator;
    const nested_func_calls = "SUM((100+.4)*20,SUMIF(A1:A20))";
    try testTokenizerInput(allocator, nested_func_calls, &[_]ExpectedToken{
        .{
            .type = .func_call,
            .str = "SUM",
        },
        .{
            .type = .l_paren,
            .str = "(",
        },
        .{
            .type = .l_paren,
            .str = "(",
        },
        .{
            .type = .num_literal,
            .str = "100",
        },
        .{
            .type = .plus,
            .str = "+",
        },
        .{
            .type = .num_literal,
            .str = ".4",
        },
        .{
            .type = .r_paren,
            .str = ")",
        },
        .{
            .type = .mult,
            .str = "*",
        },
        .{
            .type = .num_literal,
            .str = "20",
        },
        .{
            .type = .arg_sep,
            .str = ",",
        },
        .{
            .type = .func_call,
            .str = "SUMIF",
        },
        .{
            .type = .l_paren,
            .str = "(",
        },
        .{
            .type = .cell_ref,
            .str = "A1",
        },
        .{
            .type = .range_op,
            .str = ":",
        },
        .{
            .type = .cell_ref,
            .str = "A20",
        },
        .{
            .type = .r_paren,
            .str = ")",
        },
        .{
            .type = .r_paren,
            .str = ")",
        },
    });

    const str_lit_inside_func = "LENB(\"howdy\")";
    try testTokenizerInput(allocator, str_lit_inside_func, &[_]ExpectedToken{
        .{
            .type = .func_call,
            .str = "LENB",
        },
        .{
            .type = .l_paren,
            .str = "(",
        },
        .{
            .type = .str_literal,
            .str = "\"howdy\"",
        },
        .{
            .type = .r_paren,
            .str = ")",
        },
    });
}
