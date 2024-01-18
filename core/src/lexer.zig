const std = @import("std");

const float_t = f64;
const int_t = i64;

/// Cell reference for indexing
pub const CellRef = struct { row: usize, col: usize };

/// Tagged union of possible literal values
pub const Literal = union(enum) {
    /// or, not applicable (e.g. operators)
    none: void,
    boolean: bool,
    integer: int_t,
    float: float_t,
    string: []const u8,
    /// like string, except it's a slice (no mem alloc)
    keyword: []const u8,
    cell_ref: CellRef,
};

/// Reference: https://support.microsoft.com/en-us/office/calculation-operators-and-precedence-in-excel-48be406d-4975-4d31-b2b8-7af9e0e2878a
/// TODO: read all this carefully:
/// https://support.microsoft.com/en-us/office/calculation-operators-and-precedence-in-excel-48be406d-4975-4d31-b2b8-7af9e0e2878a
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
    sheet_ref,
    /// end of input
    eof,
};

fn isDigit(c: u8) bool {
    return '0' <= c and c <= '9';
}

inline fn isAlphaLower(c: u8) bool {
    return 'a' <= c and c <= 'z';
}

inline fn isAlphaUpper(c: u8) bool {
    return 'A' <= c and c <= 'Z';
}

fn isAlpha(c: u8) bool {
    return isAlphaUpper(c) or isAlphaLower(c);
}

fn isAlphaNumeric(c: u8) bool {
    return isDigit(c) or isAlpha(c);
}

fn interpretString(allocator: std.mem.Allocator, str: []const u8, quote_char: u8) ![]const u8 {
    var octets = try std.ArrayListUnmanaged(u8).initCapacity(allocator, str.len);
    var i: usize = 0;
    while (i < str.len) {
        const c = str[i];
        const at_end = i == str.len - 1;
        if (c == quote_char) {
            if (at_end) {
                return error.UnterminatedEscapeChar;
            }
            i += 1;
            const next = str[i];
            if (next == quote_char) {
                try octets.append(allocator, next);
            } else {
                return error.InvalidEscapeSequence;
            }
        } else {
            try octets.append(allocator, c);
        }
        i += 1;
    }
    const result = try octets.toOwnedSlice(allocator);
    // deinit is unnecessary here
    return result;
}

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
    /// Currently, only strings take up extra memory, but
    /// caller can just call `deinit` unconditionally.
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

fn getAlphaOffset(letter: u8) usize {
    return @intCast(letter - 'A');
}

const ALPHABET_SIZE = 'Z' - 'A';

/// Computes the offset assuming a long array like:
/// A, B, C, ... Z, AA, AB, ... ZY, ZZ
fn getDoubleAlphaOffset(left: u8, right: u8) usize {
    const offset_left = getAlphaOffset(left);
    const offset_right = getAlphaOffset(right);
    return ALPHABET_SIZE + ALPHABET_SIZE * offset_left + offset_right;
}

fn getSingleCharToken(c: u8) ?TokenType {
    return switch (c) {
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
        else => null,
    };
}

fn getTwoCharToken(left: u8, right: u8) ?TokenType {
    return switch (left) {
        '<' => switch (right) {
            '=' => .lte,
            '>' => .neq,
            else => .lt,
        },
        '>' => switch (right) {
            '=' => .gte,
            else => .gt,
        },
        else => null,
    };
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

    fn peek(self: *Self) u8 {
        return self.input[self.tick];
    }

    /// peeks the next 3 characters, used
    /// for cell ref (column part), for a total
    /// length of 4, e.g. `$AZ$`
    fn peek3(self: *Self) []const u8 {
        var end = @min(self.input.len, self.tick + 3);
        return self.input[self.tick..end];
    }

    fn isEof(self: *Self) bool {
        return self.tick >= self.input.len;
    }

    fn atEnd(self: *Self) bool {
        return self.tick == self.input.len - 1;
    }

    /// Return current, then advance tick
    fn advance(self: *Self) u8 {
        const c = self.input[self.tick];
        self.tick += 1;
        return c;
    }

    /// need to call token.deinit()
    ///
    /// if error occurs, caller should check tick
    pub fn next(self: *Self, allocator: std.mem.Allocator) !Token {
        const start = self.tick;
        if (self.isEof()) {
            return Token{
                .type = TokenType.eof,
                .start = start,
                .end = start,
                .lexeme = self.input[start..start],
                .literal = .{
                    .none = undefined,
                },
            };
        }

        var c = self.advance();
        const maybe_tok = getSingleCharToken(c);
        if (maybe_tok) |tok_type| {
            const end = start + 1;
            return Token{
                .type = tok_type,
                .start = start,
                .end = end,
                .lexeme = self.input[start..end],
                .literal = .{
                    .none = undefined,
                },
            };
        }

        // two-character tokens
        if (!self.isEof()) {
            const left = c;
            const right = self.peek();
            const two_char_tok = getTwoCharToken(left, right);
            if (two_char_tok) |tok_type| {
                const end = start + 2;
                self.tick += 1;
                return Token{
                    .type = tok_type,
                    .start = start,
                    .end = end,
                    .lexeme = self.input[start..end],
                    .literal = .{
                        .none = undefined,
                    },
                };
            }
        }
        if (c == '\'') {
            // leading single quote (') can be either unterminated
            // sheet name or string. Sheet name has closing quote
            // (up to 31 characters long within).
            const MAX_SHEET_NAME = 31;
            var tok_type = TokenType.str_literal;
            var lexeme_len: usize = 1;
            var char = c;
            while (lexeme_len <= MAX_SHEET_NAME and !self.isEof()) {
                const next_char = self.peek();
                if (char == '\'' and next_char == '!') {
                    tok_type = TokenType.sheet_ref;
                    _ = self.advance();
                    lexeme_len += 1; // + bang
                    break;
                }
                char = self.advance();
                lexeme_len += 1;
            }
            if (tok_type == .sheet_ref) {
                // allocate memory for new string
                const end = start + lexeme_len;
                const lexeme = self.input[start..end];
                // TODO: subroutine for extracting string
                // handling escape characters
                return Token{
                    .type = tok_type,
                    .start = start,
                    .end = end,
                    .lexeme = lexeme,
                    .literal = .{
                        .none = undefined,
                    },
                };
            }
            // keep going till end
            while (!self.isEof()) {
                _ = self.advance();
                lexeme_len += 1;
            }
            const end = start + lexeme_len;
            const lexeme = self.input[start..end];
            // start at 1 to skip the single quote
            const str_lit = try interpretString(allocator, lexeme[1..], '\'');
            return Token{
                .type = tok_type,
                .start = start,
                .end = end,
                .lexeme = lexeme,
                .literal = .{
                    .string = str_lit,
                },
            };
        }
        if (c == '"') {
            var lexeme_len: usize = 0;
            var octets = try std.ArrayListUnmanaged(u8).initCapacity(allocator, 0);
            while (!self.isEof()) {
                lexeme_len += 1;
                c = self.advance();
                if (c == '"') {
                    const maybe_quote = self.peek();
                    var end_of_string = true;
                    if (maybe_quote == '"') {
                        end_of_string = false;
                        c = self.advance();
                        lexeme_len += 1;
                    }
                    if (end_of_string) {
                        break;
                    }
                }
                try octets.append(allocator, c);
            }
            const literal = try octets.toOwnedSlice(allocator);
            const end = start + lexeme_len;
            return Token{
                .type = .str_literal,
                .start = start,
                .end = end,
                .lexeme = self.input[start..end],
                .literal = .{
                    .string = literal,
                },
            };
        }
        var is_digit = isDigit(c);
        if (is_digit) {
            var seen_dot = false;
            var char = c;
            while (is_digit and !self.isEof()) {
                const next_c = self.peek();
                is_digit = isDigit(next_c);
                if (!is_digit) {
                    if (next_c != '.') {
                        break;
                    }
                    if (seen_dot) {
                        return error.MoreThanOneDotInFloat;
                    }
                    seen_dot = true;
                }
                char = self.advance();
            }
            const end = self.tick;
            const lexeme = self.input[start..end];
            if (seen_dot) {
                // float
                const float = try std.fmt.parseFloat(float_t, lexeme);
                return Token{
                    .type = .num_literal,
                    .start = start,
                    .end = end,
                    .lexeme = lexeme,
                    .literal = .{
                        .float = float,
                    },
                };
            }
            const int = try std.fmt.parseInt(int_t, lexeme, 10);
            return Token{
                .type = .num_literal,
                .start = start,
                .end = end,
                .lexeme = lexeme,
                .literal = .{
                    .integer = int,
                },
            };
        }

        // alpha-numeric keywords
        const save_tick = self.tick; // reset back to here
        // isAlpha is sufficient
        // since isDigit cannot be true here
        if (isAlpha(c)) {
            var char = c;
            while (isAlphaNumeric(char) and !self.isEof()) {
                char = self.advance();
            }
            // no longer alphanumeric
            const end = self.tick;
            const lexeme = self.input[start..end];
            if (char == '(') {
                return Token{
                    .type = .func_call,
                    .start = start,
                    .end = end,
                    .lexeme = lexeme,
                    .literal = .{
                        .keyword = lexeme[0..(lexeme.len - 1)],
                    },
                };
            }
            if (char == '!') {
                const value = try allocator.alloc(u8, lexeme.len);
                // TODO: handle escape characters if any
                std.mem.copy(u8, value, lexeme[0..(lexeme.len - 1)]);
                return Token{
                    .type = .sheet_ref,
                    .start = start,
                    .end = end,
                    .lexeme = lexeme,
                    .literal = .{ .string = value },
                };
            }
            // true, false literals
            if (std.mem.eql(u8, "TRUE", lexeme) or std.mem.eql(u8, "true", lexeme)) {
                return Token{
                    .type = .true,
                    .start = start,
                    .end = end,
                    .lexeme = lexeme,
                    .literal = .{
                        .boolean = true,
                    },
                };
            }
            if (std.mem.eql(u8, "FALSE", lexeme) or std.mem.eql(u8, "false", lexeme)) {
                return Token{
                    .type = .false,
                    .start = start,
                    .end = end,
                    .lexeme = lexeme,
                    .literal = .{
                        .boolean = false,
                    },
                };
            }
        }
        self.tick = save_tick;

        // cell refs
        if (isAlphaUpper(c) or c == '$') {
            const peeked3 = self.peek3();
            var col_ref: [2]u8 = .{ 0, 0 };
            var count_alpha: usize = if (c == '$') 0 else 1;
            if (count_alpha == 1) {
                col_ref[0] = c;
            }
            var ticks_to_advance: usize = 0;
            for (peeked3) |char| {
                if (count_alpha == 2 or ticks_to_advance == 3) {
                    break;
                }
                if (!isAlphaUpper(char) and char != '$') {
                    break;
                }
                ticks_to_advance += 1;
                if (isAlphaUpper(char)) {
                    count_alpha += 1;
                    col_ref[count_alpha - 1] = char;
                }
            }
            if (count_alpha == 1 or count_alpha == 2) {
                var col_index: usize = switch (count_alpha) {
                    1 => getAlphaOffset(col_ref[0]),

                    2 => getDoubleAlphaOffset(col_ref[0], col_ref[1]),
                    else => unreachable,
                };
                // get row index
                self.tick += ticks_to_advance;
                const digit_start = self.tick;
                if (!self.atEnd()) {
                    var char = self.advance();
                    var peeked = self.peek();
                    while (isDigit(peeked) and !self.atEnd()) {
                        char = self.advance();
                        peeked = self.peek();
                    }
                }
                const end = self.tick;
                const lexeme = self.input[start..end];
                const row_str = self.input[digit_start..end];
                const row_number = try std.fmt.parseUnsigned(usize, row_str, 10);
                return Token{
                    .type = .cell_ref,
                    .start = start,
                    .end = end,
                    .lexeme = lexeme,
                    .literal = .{
                        .cell_ref = .{
                            .row = row_number - 1,
                            .col = col_index,
                        },
                    },
                };
            }
        }

        // catch-all
        return error.UnexpectedCharacter;
    }
};

const ExpectedToken = struct {
    str: []const u8,
    type: TokenType,
};

fn testTokenizerInput(allocator: std.mem.Allocator, input: []const u8, expected: []const ExpectedToken) !void {
    std.debug.print("\nINPUT: {s}\n", .{input});
    var tokenizer = Tokenizer.new(input);
    var token = try tokenizer.next(allocator);
    var i: usize = 0;
    while (token.type != .eof) {
        const expected_token = expected[i];
        try std.testing.expectEqualStrings(expected_token.str, input[token.start..token.end]);
        try std.testing.expectEqual(expected_token.type, token.type);
        i += 1;
        token.deinit(allocator);
        token = try tokenizer.next(allocator);
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
            .str = "Sheet1!",
            .type = .sheet_ref,
        },
        .{
            .str = "F5",
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
            .str = "'Name with spaces'!",
            .type = .sheet_ref,
        },
        .{
            .str = "F5",
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
            .str = "$Z$Q8989",
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
            .str = " ",
        },
        .{
            .type = .space,
            .str = " ",
        },
        .{
            .type = .space,
            .str = " ",
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
            .str = "SUM(",
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
            .str = "PRODUCT(",
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
            .str = "SUM(",
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
            .str = "SUMIF(",
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
            .str = "LENB(",
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
