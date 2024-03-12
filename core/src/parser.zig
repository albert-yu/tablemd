const std = @import("std");
const lexer = @import("lexer.zig");
const string_utils = @import("string_utils.zig");

const float_t = lexer.float_t;
const int_t = lexer.int_t;

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

pub const BinaryOp = enum {
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

pub const Expr = union(enum) {
    unknown: void,
    literal: ExprLiteral,
    unary: *ExprUnary,
    binary: *ExprBinary,
    variadic: *ExprVariadic,
    grouping: *ExprGrouping,

    /// caller must free with `.destroySelf`
    pub fn createLiteral(allocator: std.mem.Allocator, literal: ExprLiteral) error{ OutOfMemory, TokenError }!*Expr {
        var expr: *Expr = try allocator.create(Expr);
        expr.* = Expr{
            .literal = switch (literal) {
                .string => try copyStrLiteral(allocator, literal.string),
                else => literal,
            },
        };
        return expr;
    }

    pub fn createUnaryOp(allocator: std.mem.Allocator, op: UnaryOp, operand: *Expr) error{ OutOfMemory, TokenError }!*Expr {
        var expr = try allocator.create(Expr);
        var unary = try allocator.create(ExprUnary);
        unary.* = ExprUnary{
            .op = op,
            .operand = operand,
        };
        expr.* = Expr{
            .unary = unary,
        };
        return expr;
    }

    pub fn createBinaryOp(allocator: std.mem.Allocator, left: *Expr, op: BinaryOp, right: *Expr) error{ OutOfMemory, TokenError }!*Expr {
        var expr: *Expr = try allocator.create(Expr);
        var binary_inner = try allocator.create(ExprBinary);
        binary_inner.* = ExprBinary{
            .op = op,
            .left = left,
            .right = right,
        };
        expr.* = Expr{
            .binary = binary_inner,
        };
        return expr;
    }

    pub fn createGrouping(allocator: std.mem.Allocator, operand: *Expr) error{ OutOfMemory, TokenError }!*Expr {
        var expr: *Expr = try allocator.create(Expr);
        var grouping_inner = try allocator.create(ExprGrouping);
        grouping_inner.* = ExprGrouping{
            .operand = operand,
        };
        expr.* = Expr{
            .grouping = grouping_inner,
        };
        return expr;
    }

    pub fn createVariadic(allocator: std.mem.Allocator, expr_variadic: ExprVariadic) error{ OutOfMemory, TokenError }!*Expr {
        var expr: *Expr = try allocator.create(Expr);
        var variadic_inner = try allocator.create(ExprVariadic);
        variadic_inner.* = expr_variadic;
        expr.* = Expr{
            .variadic = variadic_inner,
        };
        return expr;
    }

    pub fn destroySelf(self: *Expr, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .unknown => {},
            .literal => {
                switch (self.literal) {
                    .string => allocator.free(self.literal.string),
                    else => {
                        // do nothing
                    },
                }
            },
            .unary => {
                var allocated = self.unary.operand;
                allocated.destroySelf(allocator);
                allocator.destroy(self.unary);
            },
            .binary => {
                var allocated_l = self.binary.left;
                allocated_l.destroySelf(allocator);

                var allocated_r = self.binary.right;
                allocated_r.destroySelf(allocator);

                allocator.destroy(self.binary);
            },
            .variadic => {
                var func = self.variadic.func;
                allocator.free(func);
                for (self.variadic.args) |arg| {
                    arg.destroySelf(allocator);
                }
                allocator.free(self.variadic.args);
                allocator.destroy(self.variadic);
            },
            .grouping => {
                var expr = self.grouping.operand;
                expr.destroySelf(allocator);
                allocator.destroy(self.grouping);
            },
        }
        allocator.destroy(self);
    }

    fn toAstStringInner(self: *Expr, allocator: std.mem.Allocator, char_list: *std.ArrayListUnmanaged(u8)) !void {
        switch (self.*) {
            .unknown => try char_list.appendSlice(allocator, "unknown"),
            .literal => {
                switch (self.literal) {
                    .none => try char_list.appendSlice(allocator, "none"),
                    .boolean => {
                        const s = if (self.literal.boolean) "true" else "false";
                        try char_list.appendSlice(allocator, s);
                    },
                    .integer => {
                        const s = try std.fmt.allocPrint(allocator, "{d}", .{self.literal.integer});
                        defer allocator.free(s);
                        try char_list.appendSlice(allocator, s);
                    },
                    .float => {
                        const s = try std.fmt.allocPrint(allocator, "{d}", .{self.literal.float});
                        defer allocator.free(s);
                        try char_list.appendSlice(allocator, s);
                    },
                    .string => {
                        const s = self.literal.string;
                        try char_list.append(allocator, '"');
                        try char_list.appendSlice(allocator, s);
                        try char_list.append(allocator, '"');
                    },
                    .keyword => {
                        const s = self.literal.keyword;
                        try char_list.appendSlice(allocator, s);
                    },
                    .cell_ref => {
                        const cell_ref = self.literal.cell_ref;
                        const row_col = try std.fmt.allocPrint(allocator, "({d}, {d})", .{ cell_ref.row, cell_ref.col });
                        defer allocator.free(row_col);
                        try char_list.appendSlice(allocator, row_col);
                    },
                }
            },
            .unary => {
                const op = switch (self.unary.op) {
                    .ref_op => "&",
                    .neg => "-",
                    .pound => "#",
                    .percent => "%",
                };
                try char_list.append(allocator, '(');
                try char_list.appendSlice(allocator, op);
                try char_list.append(allocator, ' ');
                var operand = self.unary.operand;
                try operand.toAstStringInner(allocator, char_list);
                try char_list.append(allocator, ')');
            },
            .binary => {
                const op = switch (self.binary.op) {
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
                var left = self.binary.left;
                try left.toAstStringInner(allocator, char_list);
                try char_list.append(allocator, ' ');
                var right = self.binary.right;
                try right.toAstStringInner(allocator, char_list);
                try char_list.append(allocator, ')');
            },
            .variadic => {
                try char_list.append(allocator, '(');
                var func = self.variadic.func;
                try char_list.appendSlice(allocator, func);
                try char_list.append(allocator, ' ');
                for (self.variadic.args, 0..) |arg, i| {
                    try arg.toAstStringInner(allocator, char_list);
                    if (i != self.variadic.args.len - 1) {
                        try char_list.append(allocator, ' ');
                    }
                }
                try char_list.append(allocator, ')');
            },
            .grouping => {
                try char_list.append(allocator, '(');
                var operand = self.grouping.operand;
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

const ExprOrTok = union(enum) {
    tok: lexer.Token,
    expr: *Expr,
};

fn copyStrLiteral(allocator: std.mem.Allocator, s: []const u8) !ExprLiteral {
    const str = try string_utils.copyString(allocator, s);
    return ExprLiteral{
        .string = str,
    };
}

const Parser = struct {
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
        std.log.err("{s}\n", .{message});
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

    fn arguments(self: *Parser, allocator: std.mem.Allocator) error{ OutOfMemory, TokenError }![]*Expr {
        var args = try std.ArrayListUnmanaged(*Expr).initCapacity(allocator, 1);
        if (!self.matchOne(.r_paren)) {
            while (true) {
                var arg = try self.expression(allocator);
                try args.append(allocator, arg);
                if (!self.matchOne(.arg_sep)) {
                    break;
                }
            }
        }
        return args.toOwnedSlice(allocator);
    }

    fn primary(self: *Parser, allocator: std.mem.Allocator) error{ OutOfMemory, TokenError }!*Expr {
        if (self.matchOne(.false)) {
            var expr = try Expr.createLiteral(allocator, .{
                .boolean = false,
            });
            return expr;
        }
        if (self.matchOne(.true)) {
            var expr = try Expr.createLiteral(allocator, .{
                .boolean = true,
            });
            return expr;
        }
        if (self.match(&[_]lexer.TokenType{ .num_literal, .str_literal, .cell_ref })) {
            var expr = try Expr.createLiteral(allocator, self.previous().literal);
            return expr;
        }
        if (self.matchOne(.func_call)) {
            var func = try string_utils.copyString(allocator, self.previous().literal.keyword);
            errdefer allocator.free(func);
            var args = try self.arguments(allocator);
            errdefer {
                for (args) |arg| {
                    arg.destroySelf(allocator);
                }
                allocator.free(args);
            }
            var expr = try Expr.createVariadic(allocator, .{
                .func = func,
                .args = args,
            });
            return expr;
        }
        if (self.matchOne(.l_paren)) {
            var expr = try self.expression(allocator);

            _ = try self.consume(.r_paren, "Expected ')' after expression.");
            return try Expr.createGrouping(allocator, expr);
        }

        // TODO: std.log.err and .warn fail the test
        std.log.debug("unexpected token {}\n", .{self.peek().type});
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
        errdefer expr.destroySelf(allocator);

        while (self.match(&[_]lexer.TokenType{
            .pow,
        })) {
            var operator = self.previous();
            var right = try self.unaryPre(allocator);
            errdefer right.destroySelf(allocator);
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
        errdefer expr.destroySelf(allocator);

        while (self.match(&[_]lexer.TokenType{
            .mult,
            .div,
        })) {
            var operator = self.previous();
            var right = try self.exp(allocator);
            errdefer right.destroySelf(allocator);
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
        errdefer expr.destroySelf(allocator);
        while (self.match(&[_]lexer.TokenType{
            .minus,
            .plus,
        })) {
            var operator = self.previous();
            var right = try self.factor(allocator);
            errdefer right.destroySelf(allocator);
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

/// Parse the input into an expression.
/// Caller must free the returned expression.
pub fn parse(allocator: std.mem.Allocator, input: []const u8) !*Expr {
    var tokenizer = lexer.Tokenizer.new(input);
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
    return expr;
}

const ParserTestCase = struct {
    input: []const u8,
    expected_str: []const u8,
};

fn testParse(allocator: std.mem.Allocator, test_case: ParserTestCase) !void {
    const expr = try parse(allocator, test_case.input);
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

    const expr = try parse(allocator, "5+4");
    defer expr.destroySelf(allocator);

    switch (expr.*) {
        .binary => {
            try std.testing.expectEqual(BinaryOp.plus, expr.binary.op);
            const left = expr.binary.left;
            const right = expr.binary.right;
            var parsed_right = switch (right.*) {
                .literal => switch (right.literal) {
                    .integer => right.literal.integer,
                    else => -1,
                },
                else => -1,
            };
            const expected_right: int_t = 4;
            try std.testing.expectEqual(expected_right, parsed_right);

            var parsed_left = switch (left.*) {
                .literal => switch (left.literal) {
                    .integer => left.literal.integer,
                    else => -1,
                },
                else => -1,
            };
            const expected_left: int_t = 5;
            try std.testing.expectEqual(expected_left, parsed_left);
        },
        else => {
            try std.testing.expect(false);
        },
    }

    try testParse(allocator, .{ .input = "2^0.0", .expected_str = "(^ 2 0)" });
    try testParse(allocator, .{ .input = "\"a string\"", .expected_str = "\"a string\"" });
    try testParse(allocator, .{ .input = "SUM(1,2)", .expected_str = "(SUM 1 2)" });
}

test "white space" {
    const allocator = std.testing.allocator;
    try testParse(allocator, .{ .input = "2 - 3", .expected_str = "(- 2 3)" });
    try testParse(allocator, .{ .input = "-2+ 3", .expected_str = "(+ (- 2) 3)" });
}

test "precedence" {
    const allocator = std.testing.allocator;
    try testParse(allocator, .{ .input = "2+3*4", .expected_str = "(+ 2 (* 3 4))" });
    try testParse(allocator, .{ .input = "2*3+4", .expected_str = "(+ (* 2 3) 4)" });
    try testParse(allocator, .{ .input = "2*3+4*5", .expected_str = "(+ (* 2 3) (* 4 5))" });
    try testParse(allocator, .{ .input = "2*3*4", .expected_str = "(* (* 2 3) 4)" });
    try testParse(allocator, .{ .input = "2^3^4", .expected_str = "(^ (^ 2 3) 4)" });
    try testParse(allocator, .{ .input = "2^3*4", .expected_str = "(* (^ 2 3) 4)" });
    try testParse(allocator, .{ .input = "2*3^4", .expected_str = "(* 2 (^ 3 4))" });
    // Yes, this is actually how precedence works in Google Sheets!
    try testParse(allocator, .{ .input = "-2^2", .expected_str = "(^ (- 2) 2)" });
}

test "invalid input leak" {
    const allocator = std.testing.allocator;
    const result = parse(allocator, "1+");
    try std.testing.expectError(error.TokenError, result);

    const result_2 = parse(allocator, "1 $");
    try std.testing.expectError(error.UnexpectedCharacter, result_2);
}
