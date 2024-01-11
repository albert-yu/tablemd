const std = @import("std");

const float_t = f64;
const int_t = i64;

const Literal = union(enum) {
    /// or, not applicable (e.g. operators)
    none: void,
    boolean: bool,
    integer: int_t,
    float: float_t,
    string: []const u8,
};

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
        var tick: usize = 0;
        for (arrays) |array| {
            for (array) |str| {
                merged[tick] = str;
                tick += 1;
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
    "tick",
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

const CELL_REFS = [_][]const u8{
    // not allowed in sheet name: [ ] * / \ ? :
    "(([a-zA-Z0-9]{1,31}|'[a-zA-Z0-9_ \\-\\$!\\^&#%@]{1,31}')!)?\\$?[a-zA-Z]{1,2}\\$?[0-9]+",
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
    // string with leading single quote and without closing
    "'[^']*",
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
    /// matched string
    lexeme: []const u8,
    literal: Literal,

    const Self = @This();

    /// Frees any memory that this token may have taken up.
    ///
    /// Currently, only strings take up extra memory.
    pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        switch (self.literal) {
            .string => {
                allocator.free(self.literal.string);
            },
            else => {
                // no-op
            },
        }
    }
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

fn getSingleCharToken(c: u8) ?TokenType {
    const tok = switch (c) {
        '+' => .plus,
        '=' => .eq,
        '-' => .minus,
        '*' => .mult,
        '^' => .pow,
        '/' => .div,
        '(' => .l_paren,
        '[' => .l_bracket,
        '{' => .l_brace,
        ')' => .r_paren,
        ']' => .r_bracket,
        '}' => .r_brace,
        ',' => .arg_sep,
        ';' => .row_sep,
        '&' => .concat,
        ':' => .range_op,
        '%' => .percent,
        '#' => .pound,
        '@' => .ref_op,
        else => undefined,
    };
    return tok;
}

pub const Tokenizer = struct {
    input: []const u8,
    tick: usize,
    const Self = @This();

    pub fn new(s: []const u8) Self {
        return Self{
            .input = s,
            .tick = 0,
        };
    }

    /// need to call token.deinit()
    pub fn next(self: *Self, allocator: std.mem.Allocator) !Token {
        _ = allocator;
        if (self.tick >= self.input.len) {
            return Token{
                .type = TokenType.eof,
                .start = self.tick,
                .end = self.tick,
                .lexeme = "",
                .literal = .{
                    .none = undefined,
                },
            };
        }
        const start = self.tick;
        const c = self.input[self.tick];
        _ = c;
        self.tick += 1;
        const maybe_tok = getSingleCharToken(u8);
        if (maybe_tok) |tok_type| {
            return Token{
                .type = tok_type,
                .start = start,
                .end = start + 1,
                .lexeme = "",
                .literal = .{
                    .none = void,
                },
            };
        }
        var token = Token{
            .type = TokenType.unknown,
            .start = start,
            .end = start + 1,
            .lexeme = "",
            .literal = .{
                .none = void,
            },
        };
        _ = token;

        return error.UnexpectedCharacter;
    }
};

const ExpectedToken = struct {
    str: []const u8,
    type: TokenType,
};

fn testTokenizerInput(allocator: std.mem.Allocator, input: []const u8, expected: []const ExpectedToken) !void {
    var tokenizer = Tokenizer.new(input);
    var token = try tokenizer.next(allocator);
    var i: usize = 0;
    while (token.type != .eof) {
        const expected_token = expected[i];
        try std.testing.expectEqualStrings(expected_token.str, input[token.start..token.end]);
        try std.testing.expectEqual(expected_token.type, token.type);
        i += 1;
        token.deinit(allocator);
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

    const sheet_cell_ref = "Sheet1!F5=2";
    try testTokenizerInput(allocator, sheet_cell_ref, &[_]ExpectedToken{
        .{
            .str = "Sheet1!F5",
            .type = .cell_ref,
        },
        .{
            .str = "=",
            .type = .eq,
        },
        .{
            .str = "2",
            .type = .num_literal,
        },
    });
    const sheet_cell_ref_2 = "'Name with spaces'!F5=2";
    try testTokenizerInput(allocator, sheet_cell_ref_2, &[_]ExpectedToken{
        .{
            .str = "'Name with spaces'!F5",
            .type = .cell_ref,
        },
        .{
            .str = "=",
            .type = .eq,
        },
        .{
            .str = "2",
            .type = .num_literal,
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
