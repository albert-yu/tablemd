const std = @import("std");
const lexer = @import("lexer.zig");

const float_t = lexer.float_t;
const int_t = lexer.int_t;

const Value = lexer.Literal;

const ExprLiteral = lexer.Literal;

const ExprType = enum {
    unknown,
    /// or, a leaf
    literal,
    unary,
    binary,
    variadic,
    grouping,
};

/// Not exhaustive, some are context-dependent (e.g. space, minus),
/// which are returned as unknown
fn getExprType(token_type: lexer.TokenType) ExprType {
    var expr_type: ExprType = switch (token_type) {
        .str_literal, .num_literal, .false, .true, .cell_ref => .literal,
        .ref_op, .pound, .percent => .unary,
        .plus, .mult, .div, .pow, .eq, .lt, .gt, .lte, .gte, .neq, .concat, .range_op => .binary,
        .func_call => .variadic,
        else => .unknown,
    };
    return expr_type;
}

const UnaryOp = enum {
    ref_op,
    pound,
    percent,
    neg,
};

const ExprUnary = struct {
    operand: Expr,
    op: UnaryOp,
};

const BinaryOp = enum {
    plus,
    minus,
    mult,
    div,
    pow,
    eq,
    lt,
    gt,
    lte,
    gte,
    neq,
    concat,
    range_op,
};

const ExprBinary = struct {
    left: Expr,
    right: Expr,
    op: BinaryOp,
};

const ExprVariadic = struct {
    func: []const u8,
    args: []const Expr,
};

const ExprGrouping = struct {
    operand: Expr,
};

const ExprUnion = union(enum) {
    unknown: void,
    literal: ExprLiteral,
    unary: ExprUnary,
    binary: ExprBinary,
    variadic: ExprVariadic,
    grouping: ExprGrouping,
};

// const ParserState = struct {
//     stack: std.ArrayListUnmanaged(lexer.Token),
//     prev_token: lexer.Token,
//
//     pub fn new(allocator: std.mem.Allocator) !ParserState {
//         return .{
//             .stack = try std.ArrayListUnmanaged(lexer.Token).initCapacity(allocator, 1),
//         };
//     }
//
//     pub fn deinit(self: *ParserState, allocator: std.mem.Allocator) void {
//         self.stack.deinit(allocator);
//     }
//
//     pub fn push(self: *ParserState, allocator: std.mem.Allocator, tok: lexer.Token) !void {
//         try self.stack.append(allocator, tok);
//     }
//
//     pub fn popOrNull(self: *ParserState) ?lexer.Token {
//         return self.stack.popOrNull();
//     }
//
//     pub fn empty(self: *ParserState) bool {
//         return self.stack.items.len == 0;
//     }
// };

const ExprOrTok = union(enum) {
    tok: lexer.Token,
    expr: *Expr,
};

fn isNegativeOp(prev_tok: lexer.Token, next_item: ExprOrTok) bool {
    if (prev_tok.type != .space) {
        return false;
    }
    return switch (next_item) {
        .expr => true,
        .tok => next_item.tok.isNumLiteral(),
    };
}

pub const Expr = struct {
    value: ExprUnion,

    /// caller must free with `.destroySelf`
    fn createLiteral(allocator: std.mem.Allocator, literal: ExprLiteral) !*Expr {
        var expr: *Expr = try allocator.create(Expr);
        expr.* = Expr{
            .value = .{
                .literal = literal,
            },
        };
        return expr;
    }

    fn createUnaryOp(allocator: std.mem.Allocator, op: UnaryOp, operand: *Expr) !*Expr {
        var expr: *Expr = try allocator.create(Expr);
        expr.* = Expr{
            .value = .{
                .unary = .{
                    .op = op,
                    .operand = operand,
                },
            },
        };
        return expr;
    }

    fn createBinaryOp(allocator: std.mem.Allocator, left: *Expr, op: BinaryOp, right: *Expr) !*Expr {
        var expr: *Expr = try allocator.create(Expr);
        expr.* = Expr{
            .value = .{
                .binary = .{
                    .op = op,
                    .left = left,
                    .right = right,
                },
            },
        };
        return expr;
    }

    // fn consumeGroup(allocator: std.mem.Allocator, items: []const ExprOrTok) !*Expr {
    //     _ = allocator;
    //     var expr: *Expr = undefined;
    //     var prev_expr: *Expr = undefined;
    //     _ = prev_expr;
    //     var prev_tok: lexer.Token = undefined;
    //     for (items, 0..) |item, i| {
    //         switch (item) {
    //             .tok => {
    //                 switch (item.tok.type) {
    //                     .plus => {},
    //                     .minus => {
    //                         if (i > 0 and i < items.len - 1) {
    //                             // i > 0 to ensure prev_tok exists
    //                             var next_item = items[i + 1];
    //                             var is_neg = isNegativeOp(prev_tok, next_item);
    //                             if (is_neg) {
    //                                 switch (next_item) {
    //                                     .expr => {},
    //                                 }
    //                             }
    //                         }
    //                     },
    //                     else => {},
    //                 }
    //                 prev_tok = item.tok;
    //             },
    //             .expr => {},
    //         }
    //     }
    //     return expr;
    // }

    // fn parseRecursive(allocator: std.mem.Allocator, tokenizer: lexer.Tokenizer, state: ParserState) !*Expr {
    //     var expr: *Expr = try allocator.create(Expr);
    //     var items_at_level = try std.ArrayListUnmanaged(ExprOrTok).initCapacity(allocator, 1);
    //     defer items_at_level.deinit(allocator);

    //     var matching_tok: ?lexer.Token = null;

    //     while (true) {
    //         var token = try tokenizer.next(allocator);
    //         if (token.type == .eof) {
    //             break;
    //         }
    //         switch (token.type) {
    //             .num_literal, .str_literal, .false, .true, .cell_ref, .sheet_ref, .ref_op, .pound, .percent, .minus, .plus, .minus, .mult, .div, .pow, .eq, .lt, .gt, .lte, .gte, .neq, .concat, .range_op, .space, .false, .true, .arg_sep, .row_sep => {
    //                 try items_at_level.append(.{
    //                     .tok = token,
    //                 });
    //             },
    //             .func_call, .l_paren, .l_brace, .l_bracket => {
    //                 try state.push(allocator, token);
    //                 var func_expr = try Expr.parseRecursive(allocator, tokenizer, state);
    //                 try items_at_level.append(.{
    //                     .expr = func_expr,
    //                 });
    //             },
    //             .r_paren, .r_brace, .r_bracket => {
    //                 var matching = try state.popOrNull();
    //                 if (matching) |m| {
    //                     matching_tok = m;
    //                     break;
    //                 } else {
    //                     return error.ExtraClosingBraceOrParen;
    //                 }
    //             },
    //             else => {
    //                 var res = try allocator.create(Expr);
    //                 res.* = Expr{
    //                     .value = .{
    //                         .unknown = undefined,
    //                     },
    //                 };
    //                 try items_at_level.append(.{
    //                     .expr = res,
    //                 });
    //             },
    //         }
    //         state.prev_token = token;
    //     }

    //     if (matching_tok) |tok| {
    //         switch (tok.type) {
    //             .l_paren => {
    //                 var inner_expr = try Expr.consumeGroup(allocator, items_at_level.itmes);
    //                 expr.* = .{
    //                     .value = .{
    //                         .grouping = .{
    //                             .operand = inner_expr,
    //                         },
    //                     },
    //                 };
    //             },
    //             else => {
    //                 return error.UnhandledExprOpener;
    //             },
    //         }
    //     }

    //     return expr;
    // }

    // pub fn parse(allocator: std.mem.Allocator, input: []const u8) !*Expr {
    //     var tokenizer = lexer.Tokenizer.new(input);
    //     var state = try ParserState.new(allocator);
    //     defer state.deinit(allocator);
    //     return try parseRecursive(allocator, tokenizer, state);
    // }
};

pub const Parser = struct {
    current: usize,
    tokens: lexer.Token,

    pub fn new(tokens: []const lexer.Token) Parser {
        return .{
            .current = 0,
            .tokens = tokens,
        };
    }

    fn peek(self: *Parser) lexer.Token {
        return self.tokens[self.current];
    }

    fn atEnd(self: *Parser) bool {
        return self.peek().type == .eof;
    }

    fn previous(self: *Parser) lexer.Token {
        return self.tokens[self.current - 1];
    }

    fn advance(self: *Parser) lexer.Token {
        if (!self.atEnd()) {
            self.current += 1;
        }
        return self.previous();
    }
};

/// Node on tree
pub const ExprOld = struct {
    token_type: lexer.TokenType,
    content_str: []const u8,
    value: Value,
    children: *std.ArrayListUnmanaged(*Self),

    const Self = @This();

    /// Heap allocation
    pub fn create(allocator: std.mem.Allocator, content_str: []const u8, token_type: lexer.TokenType, val: Value) !*Self {
        var result = try allocator.create(Self);
        var children = try allocator.create(std.ArrayListUnmanaged(*Self));
        children.* = try std.ArrayListUnmanaged(*Self).initCapacity(allocator, 2);
        result.* = Self{
            .children = children,
            .token_type = token_type,
            .content_str = content_str,
            .value = val,
        };
        return result;
    }

    pub fn create_empty(allocator: std.mem.Allocator) !*Self {
        return try Self.create(allocator, "", .unknown, .{ .none = undefined });
    }

    /// Also calls destroy on self and descendents
    pub fn destroySelf(self: *Self, allocator: std.mem.Allocator) void {
        for (self.children.items) |child| {
            child.destroySelf(allocator);
        }
        self.children.deinit(allocator);
        allocator.destroy(self.children);
        switch (self.value) {
            .string => allocator.free(self.value.string),
            else => {},
        }
        allocator.destroy(self);
    }

    /// caller must free
    pub fn toSexpr(self: Self, allocator: std.mem.Allocator) ![]const u8 {
        var arr = try std.ArrayListUnmanaged(u8).initCapacity(allocator, self.content_str.len);
        defer arr.deinit(allocator);

        const has_children = self.children.items.len > 0;
        if (has_children) {
            try arr.append(allocator, '(');
        }
        switch (self.value) {
            .boolean => {
                const s = if (self.value.boolean) "TRUE" else "FALSE";
                for (s) |char| {
                    try arr.append(allocator, char);
                }
            },
            .string => {
                const s = self.value.string;
                for (s) |char| {
                    try arr.append(allocator, char);
                }
            },
            .float => {
                const s = try std.fmt.allocPrint(allocator, "{d}", .{self.value.float});
                defer allocator.free(s);
                for (s) |char| {
                    try arr.append(allocator, char);
                }
            },
            else => {
                const s = self.content_str;
                for (s) |char| {
                    try arr.append(allocator, char);
                }
            },
        }
        for (self.children.items) |child| {
            try arr.append(allocator, ' ');
            const sexpr = try child.toSexpr(allocator);
            defer allocator.free(sexpr);
            for (sexpr) |char| {
                try arr.append(allocator, char);
            }
        }
        if (has_children) {
            try arr.append(allocator, ')');
        }
        return arr.toOwnedSlice(allocator);
    }

    pub fn addChild(self: *Self, allocator: std.mem.Allocator, child: *Self) !void {
        try self.children.append(allocator, child);
    }

    /// Parses string into Expression tree
    pub fn parse(allocator: std.mem.Allocator, s: []const u8) !*Self {
        var tokenizer = lexer.Tokenizer.new(s);

        var token = try tokenizer.next(allocator);
        var root = try Self.create_empty(allocator);
        var curr_node_type = getExprType(token.type);
        var has_children = false;

        var i: usize = 0;
        while (token.type != .eof) {
            i += 1;
            curr_node_type = getExprType(token.type);
            const str = s[token.start..token.end];
            switch (curr_node_type) {
                .literal => {
                    var val = token.literal;
                    if (has_children) {
                        var child = try Self.create(allocator, str, token.type, val);
                        try root.addChild(allocator, child);
                    } else {
                        root.value = val;
                        root.content_str = str;
                        root.token_type = token.type;
                    }
                },
                .unary, .binary, .variadic => {
                    var new_root = try Self.create(allocator, str, token.type, .{ .none = undefined });
                    // swap root with this new node
                    var child = root;
                    try new_root.addChild(allocator, child);
                    root = new_root;
                    has_children = true;
                },
                else => {
                    // TODO: handle nested and actually everything
                },
            }
            token = try tokenizer.next(allocator);
        }
        return root;
    }
};

const ParserTestCase = struct {
    input: []const u8,
    expected_str: []const u8,
};

fn testParse(allocator: std.mem.Allocator, test_case: ParserTestCase) !void {
    var parsed = try ExprOld.parse(allocator, test_case.input);
    defer parsed.destroySelf(allocator);
    const sexpr = try parsed.toSexpr(allocator);
    defer allocator.free(sexpr);

    try std.testing.expectEqualStrings(test_case.expected_str, sexpr);
}

test "print debug" {
    const allocator = std.testing.allocator;
    var expr = try ExprOld.create(allocator, "+", .plus, .{ .none = undefined });
    defer expr.destroySelf(allocator);
    var left = try ExprOld.create(allocator, "5", .num_literal, .{ .float = 5 });
    var right = try ExprOld.create(allocator, "4", .num_literal, .{ .float = 4 });
    try expr.addChild(allocator, left);
    try expr.addChild(allocator, right);

    const sexpr = try expr.toSexpr(allocator);
    try std.testing.expectEqualStrings("(+ 5 4)", sexpr);
    defer allocator.free(sexpr);
}

test "parse simple expressions" {
    const allocator = std.testing.allocator;
    var parsed = try ExprOld.parse(allocator, "5+4");
    defer parsed.destroySelf(allocator);
    try std.testing.expectEqual(lexer.TokenType.plus, parsed.token_type);
    const left = parsed.children.items[0];
    try std.testing.expectEqual(lexer.TokenType.num_literal, left.token_type);
    const right = parsed.children.items[1];
    var parsed_right = switch (right.value) {
        .integer => right.value.integer,
        else => -1,
    };
    const expected: int_t = 4;
    try std.testing.expectEqual(expected, parsed_right);

    try testParse(allocator, .{ .input = "2^0.0", .expected_str = "(^ 2 0)" });
    try testParse(allocator, .{ .input = "\"a string\"", .expected_str = "a string" });
}
