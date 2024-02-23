const std = @import("std");
const lexer = @import("lexer.zig");

const float_t = lexer.float_t;
const int_t = lexer.int_t;

const Value = lexer.Literal;

const ExprLiteral = lexer.Literal;

const UnaryOp = enum {
    ref_op,
    pound, // post-fix
    percent, // post-fix
    neg,
};

const ExprUnary = struct {
    operand: *Expr,
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
    left: *Expr,
    right: *Expr,
    op: BinaryOp,
};

const ExprVariadic = struct {
    func: []const u8,
    args: []const *Expr,
};

const ExprGrouping = struct {
    operand: *Expr,
};

const ExprUnion = union(enum) {
    unknown: void,
    literal: ExprLiteral,
    unary: *ExprUnary,
    binary: *ExprBinary,
    variadic: *ExprVariadic,
    grouping: *ExprGrouping,
};

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
    value: *ExprUnion,

    /// caller must free with `.destroySelf`
    pub fn createLiteral(allocator: std.mem.Allocator, literal: ExprLiteral) error{ OutOfMemory, TokenError }!*Expr {
        var expr: *Expr = try allocator.create(Expr);
        var value = try allocator.create(ExprUnion);
        value.* = ExprUnion{
            .literal = literal,
        };
        expr.* = Expr{
            .value = value,
        };
        return expr;
    }

    pub fn createUnaryOp(allocator: std.mem.Allocator, op: UnaryOp, operand: *Expr) error{ OutOfMemory, TokenError }!*Expr {
        var expr: *Expr = try allocator.create(Expr);
        var unary = try allocator.create(ExprUnion);
        var unary_inner = try allocator.create(ExprUnary);
        unary_inner.* = ExprUnary{
            .op = op,
            .operand = operand,
        };
        unary.* = ExprUnion{
            .unary = unary_inner,
        };
        expr.* = Expr{
            .value = unary,
        };
        return expr;
    }

    pub fn createBinaryOp(allocator: std.mem.Allocator, left: *Expr, op: BinaryOp, right: *Expr) error{ OutOfMemory, TokenError }!*Expr {
        var expr: *Expr = try allocator.create(Expr);
        var binary = try allocator.create(ExprUnion);
        var binary_inner = try allocator.create(ExprBinary);
        binary_inner.* = ExprBinary{
            .op = op,
            .left = left,
            .right = right,
        };
        binary.* = ExprUnion{
            .binary = binary_inner,
        };
        expr.* = Expr{
            .value = binary,
        };
        return expr;
    }

    pub fn createGrouping(allocator: std.mem.Allocator, operand: *Expr) error{ OutOfMemory, TokenError }!*Expr {
        var expr: *Expr = try allocator.create(Expr);
        var grouping = try allocator.create(ExprUnion);
        var grouping_inner = try allocator.create(ExprGrouping);
        grouping_inner.* = ExprGrouping{
            .operand = operand,
        };
        grouping.* = ExprUnion{
            .grouping = grouping_inner,
        };
        expr.* = Expr{
            .value = grouping,
        };
        return expr;
    }

    pub fn destroySelf(self: *Expr, allocator: std.mem.Allocator) void {
        switch (self.value.*) {
            .unknown => {},
            .literal => {
                // do nothing
            },
            .unary => {
                var allocated = self.value.unary.operand;
                allocated.destroySelf(allocator);
                allocator.destroy(self.value.unary);
            },
            .binary => {
                var allocated_l = self.value.binary.left;
                allocated_l.destroySelf(allocator);

                var allocated_r = self.value.binary.right;
                allocated_r.destroySelf(allocator);

                allocator.destroy(self.value.binary);
            },
            .variadic => {
                var func = self.value.variadic.func;
                allocator.free(func);
                for (self.value.variadic.args) |arg| {
                    arg.destroySelf(allocator);
                }
                allocator.free(self.value.variadic.args);
                allocator.destroy(self.value.variadic);
            },
            .grouping => {
                var expr = self.value.grouping.operand;
                expr.destroySelf(allocator);
                allocator.destroy(self.value.grouping);
            },
        }
        allocator.destroy(self.value);
        allocator.destroy(self);
    }

    fn toAstStringInner(self: *Expr, allocator: std.mem.Allocator, char_list: *std.ArrayListUnmanaged(u8)) !void {
        switch (self.value.*) {
            .unknown => try char_list.appendSlice(allocator, "unknown"),
            .literal => {
                switch (self.value.literal) {
                    .none => try char_list.appendSlice(allocator, "none"),
                    .boolean => {
                        const s = if (self.value.literal.boolean) "true" else "false";
                        try char_list.appendSlice(allocator, s);
                    },
                    .integer => {
                        const s = try std.fmt.allocPrint(allocator, "{d}", .{self.value.literal.integer});
                        defer allocator.free(s);
                        try char_list.appendSlice(allocator, s);
                    },
                    .float => {
                        const s = try std.fmt.allocPrint(allocator, "{d}", .{self.value.literal.float});
                        defer allocator.free(s);
                        try char_list.appendSlice(allocator, s);
                    },
                    .string => {
                        const s = self.value.literal.string;
                        try char_list.append(allocator, '"');
                        try char_list.appendSlice(allocator, s);
                        try char_list.append(allocator, '"');
                    },
                    .keyword => {
                        const s = self.value.literal.keyword;
                        try char_list.appendSlice(allocator, s);
                    },
                    .cell_ref => {
                        const cell_ref = self.value.literal.cell_ref;
                        const row_col = try std.fmt.allocPrint(allocator, "({d}, {d})", .{ cell_ref.row, cell_ref.col });
                        defer allocator.free(row_col);
                        try char_list.appendSlice(allocator, row_col);
                    },
                }
            },
            .unary => {
                const op = switch (self.value.unary.op) {
                    .ref_op => "&",
                    .neg => "-",
                    else => unreachable,
                };
                try char_list.append(allocator, '(');
                try char_list.appendSlice(allocator, op);
                try char_list.append(allocator, ' ');
                var operand = self.value.unary.operand;
                try operand.toAstStringInner(allocator, char_list);
                try char_list.append(allocator, ')');
            },
            .binary => {
                const op = switch (self.value.binary.op) {
                    .plus => "+",
                    .minus => "-",
                    .mult => "*",
                    .div => "/",
                    .pow => "^",
                    .eq => "=",
                    .lt => "<",
                    .gt => ">",
                    .lte => "<=",
                    .gte => ">=",
                    .neq => "<>",
                    .concat => "&",
                    .range_op => ":",
                };
                try char_list.append(allocator, '(');
                try char_list.appendSlice(allocator, op);
                try char_list.append(allocator, ' ');
                var left = self.value.binary.left;
                try left.toAstStringInner(allocator, char_list);
                try char_list.append(allocator, ' ');
                var right = self.value.binary.right;
                try right.toAstStringInner(allocator, char_list);
                try char_list.append(allocator, ')');
            },
            .variadic => {
                try char_list.append(allocator, '(');
                var func = self.value.variadic.func;
                try char_list.appendSlice(allocator, func);
                try char_list.append(allocator, ' ');
                for (self.value.variadic.args, 0..) |arg, i| {
                    try arg.toAstStringInner(allocator, char_list);
                    if (i != self.value.variadic.args.len - 1) {
                        try char_list.append(allocator, ' ');
                    }
                }
                try char_list.append(allocator, ')');
            },
            .grouping => {
                try char_list.append(allocator, '(');
                var operand = self.value.grouping.operand;
                try operand.toAstStringInner(allocator, char_list);
                try char_list.append(allocator, ')');
            },
        }
    }

    pub fn toAstString(self: *Expr, allocator: std.mem.Allocator) ![]const u8 {
        var char_list = try std.ArrayListUnmanaged(u8).initCapacity(allocator, 8);
        try self.toAstStringInner(allocator, &char_list);
        var result = try char_list.toOwnedSlice(allocator);
        return result;
    }
};

pub const Parser = struct {
    current: usize,
    tokens: []const lexer.Token,

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

    fn check(self: *Parser, tokenType: lexer.TokenType) bool {
        if (self.atEnd()) {
            return false;
        }
        return self.peek().type == tokenType;
    }

    fn consume(self: *Parser, tokenType: lexer.TokenType, message: []const u8) error{TokenError}!lexer.Token {
        if (self.check(tokenType)) {
            return self.advance();
        }
        // TODO: incorporate error message
        _ = message;
        return error.TokenError;
    }

    fn match(self: *Parser, tokenTypes: []const lexer.TokenType) bool {
        for (tokenTypes) |tokenType| {
            if (self.check(tokenType)) {
                _ = self.advance();
                return true;
            }
        }
        return false;
    }

    fn matchOne(self: *Parser, tokenType: lexer.TokenType) bool {
        if (self.check(tokenType)) {
            _ = self.advance();
            return true;
        }
        return false;
    }

    fn equality(self: *Parser, allocator: std.mem.Allocator) error{ OutOfMemory, TokenError }!*Expr {
        var expr = try self.comparison(allocator);

        while (self.match(&[_]lexer.TokenType{ .neq, .eq })) {
            var operator = self.previous();
            var right = try self.comparison(allocator);

            var op = switch (operator.type) {
                .eq => BinaryOp.eq,
                .neq => BinaryOp.neq,
                else => unreachable,
            };
            // swap
            var temp = expr;
            var new_expr = try Expr.createBinaryOp(allocator, temp, op, right);
            expr = new_expr;
        }
        return expr;
    }

    fn expression(self: *Parser, allocator: std.mem.Allocator) error{ OutOfMemory, TokenError }!*Expr {
        return try self.equality(allocator);
    }

    fn primary(self: *Parser, allocator: std.mem.Allocator) error{ OutOfMemory, TokenError }!*Expr {
        if (self.matchOne(.false)) {
            var expr = try Expr.createLiteral(allocator, .{
                .boolean = false,
            });
            return expr;
        }
        if (self.matchOne(.false)) {
            var expr = try Expr.createLiteral(allocator, .{
                .boolean = true,
            });
            return expr;
        }
        if (self.match(&[_]lexer.TokenType{ .num_literal, .str_literal })) {
            var expr = try Expr.createLiteral(allocator, self.previous().literal);
            return expr;
        }
        if (self.matchOne(.l_paren)) {
            var expr = try self.expression(allocator);

            _ = try self.consume(.r_paren, "Expected ')' after expression.");
            return try Expr.createGrouping(allocator, expr);
        }

        // TODO: is this the right return value?
        return error.TokenError;
    }

    fn unaryPre(self: *Parser, allocator: std.mem.Allocator) error{ OutOfMemory, TokenError }!*Expr {
        // TODO: unary post-fix
        if (self.match(&[_]lexer.TokenType{
            .ref_op,
            .minus,
        })) {
            var operator = self.previous();
            var right = try self.unaryPre(allocator);
            var op = switch (operator.type) {
                .ref_op => UnaryOp.ref_op,
                .minus => UnaryOp.neg,
                // TODO: others
                else => unreachable,
            };
            return try Expr.createUnaryOp(allocator, op, right);
        }
        return try self.primary(allocator);
    }

    fn exp(self: *Parser, allocator: std.mem.Allocator) error{ OutOfMemory, TokenError }!*Expr {
        var expr = try self.unaryPre(allocator);

        while (self.match(&[_]lexer.TokenType{
            .pow,
        })) {
            var operator = self.previous();
            var right = try self.unaryPre(allocator);
            var op = switch (operator.type) {
                .pow => BinaryOp.pow,
                else => unreachable,
            };
            var temp = expr;
            expr = try Expr.createBinaryOp(allocator, temp, op, right);
        }
        return expr;
    }

    fn factor(self: *Parser, allocator: std.mem.Allocator) error{ OutOfMemory, TokenError }!*Expr {
        var expr = try self.exp(allocator);

        while (self.match(&[_]lexer.TokenType{
            .mult,
            .div,
        })) {
            var operator = self.previous();
            var right = try self.unaryPre(allocator);
            var op = switch (operator.type) {
                .mult => BinaryOp.mult,
                .div => BinaryOp.div,
                else => unreachable,
            };
            var temp = expr;
            expr = try Expr.createBinaryOp(allocator, temp, op, right);
        }
        return expr;
    }

    fn term(self: *Parser, allocator: std.mem.Allocator) error{ OutOfMemory, TokenError }!*Expr {
        var expr = try self.factor(allocator);
        while (self.match(&[_]lexer.TokenType{
            .minus,
            .plus,
        })) {
            var operator = self.previous();
            var right = try self.unaryPre(allocator);
            var op = switch (operator.type) {
                .minus => BinaryOp.minus,
                .plus => BinaryOp.plus,
                else => unreachable,
            };
            var temp = expr;
            expr = try Expr.createBinaryOp(allocator, temp, op, right);
        }
        return expr;
    }

    fn comparison(self: *Parser, allocator: std.mem.Allocator) error{ OutOfMemory, TokenError }!*Expr {
        var expr = try self.term(allocator);

        while (self.match(&[_]lexer.TokenType{
            .gt,
            .gte,
            .lt,
            .lte,
        })) {
            var operator = self.previous();
            var right = try self.term(allocator);
            var op = switch (operator.type) {
                .gt => BinaryOp.gt,
                .gte => BinaryOp.gte,
                .lt => BinaryOp.lt,
                .lte => BinaryOp.lte,
                else => unreachable,
            };
            var temp = expr;
            expr = try Expr.createBinaryOp(allocator, temp, op, right);
        }
        return expr;
    }

    pub fn parse(self: *Parser, allocator: std.mem.Allocator) error{ OutOfMemory, TokenError }!*Expr {
        var expr = try self.expression(allocator);
        return expr;
    }
};

const ParserTestCase = struct {
    input: []const u8,
    expected_str: []const u8,
};

fn testParse(allocator: std.mem.Allocator, test_case: ParserTestCase) !void {
    var tokenizer = lexer.Tokenizer.new(test_case.input);
    const tokens = try tokenizer.tokenize(allocator);
    defer {
        for (tokens) |token| {
            var t = token; // discard const
            t.deinit(allocator);
        }
        allocator.free(tokens);
    }

    var parser = Parser.new(tokens);
    const expr = try parser.parse(allocator);
    defer expr.destroySelf(allocator);

    const sexpr = try expr.toAstString(allocator);
    defer allocator.free(sexpr);

    try std.testing.expectEqualStrings(test_case.expected_str, sexpr);
}

test "print debug" {
    const allocator = std.testing.allocator;
    var four = try Expr.createLiteral(allocator, .{
        .integer = 4,
    });
    var five = try Expr.createLiteral(allocator, .{
        .integer = 5,
    });
    var expr = try Expr.createBinaryOp(allocator, five, .plus, four);
    defer expr.destroySelf(allocator);

    const sexpr = try expr.toAstString(allocator);
    defer allocator.free(sexpr);
    try std.testing.expectEqualStrings("(+ 5 4)", sexpr);
}

test "parse simple expressions" {
    const allocator = std.testing.allocator;
    var tokenizer = lexer.Tokenizer.new("5+4");

    const tokens = try tokenizer.tokenize(allocator);
    defer {
        for (tokens) |token| {
            var t = token; // discard const
            t.deinit(allocator);
        }
        allocator.free(tokens);
    }
    var parser = Parser.new(tokens);
    const expr = try parser.parse(allocator);
    defer expr.destroySelf(allocator);

    switch (expr.value.*) {
        .binary => {
            try std.testing.expectEqual(BinaryOp.plus, expr.value.binary.op);
            // const left = expr.value.binary.left;
            const right = expr.value.binary.right;
            var parsed_right = switch (right.value.*) {
                .literal => switch (right.value.literal) {
                    .integer => right.value.literal.integer,
                    else => -1,
                },
                else => -1,
            };
            const expected: int_t = 4;
            try std.testing.expectEqual(expected, parsed_right);
        },
        else => {
            try std.testing.expect(false);
        },
    }

    try testParse(allocator, .{ .input = "2^0.0", .expected_str = "(^ 2 0)" });
    try testParse(allocator, .{ .input = "\"a string\"", .expected_str = "a string" });
}
