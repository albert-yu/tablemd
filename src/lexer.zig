const Token = enum {
    whitespace,
    unknown,
    l_paren,
    l_bracket,
    l_brace,
    r_paren,
    r_bracket,
    r_brace,
    arg_sep,
    row_sep,
    eq,
    neq,
    lt,
    gt,
    lte,
    gte,
    plus,
    minus,
    mult,
    div,
    pow,
    concat,
    range_op,
    percent,
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

pub const Tokenizer = struct {
    input: []u8,
    index: u64,
    const Self = @This();
    pub fn init(s: []u8) void {
        Self.input = s;
        Self.index = 0;
    }

    pub fn next() !Token {
        if (Self.index >= Self.input.len) {
            return Token.eof;
        }
        const c = Self.input[Self.index];
        const token = switch (c) {
            '(' => Token.l_paren,
            '[' => Token.l_bracket,
            '{' => Token.l_brace,
            ')' => Token.r_paren,
            ']' => Token.r_bracket,
        };

        Self.index += 1;
        return token;
    }
};
