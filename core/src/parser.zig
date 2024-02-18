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
    pound, // post-fix
    percent, // post-fix
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

    pub fn destroySelf(self: *Expr, allocator: std.mem.Allocator) void {
        switch (self.value) {
            .unknown => {},
            .literal => {
                switch (self.value.literal) {
                    .string => {
                        allocator.free(self.value.literal.string);
                    },
                    else => {
                        // do nothing
                    },
                }
            },
            .unary => {
                var allocated = self.value.unary.operand;
                allocated.destroySelf(allocator);
            },
            .binary => {
                var allocated_l = self.value.binary.left;
                allocated_l.destroySelf(allocator);

                var allocated_r = self.value.binary.right;
                allocated_r.destroySelf(allocator);
            },
            .variadic => {
                var func = self.value.variadic.func;
                allocator.free(func);
                for (self.value.variadic.args) |arg| {
                    arg.destroySelf(allocator);
                }
                allocator.free(self.value.variadic.args);
            },
            .grouping => {
                var expr = self.value.grouping.operand;
                expr.destroySelf(allocator);
            },
        }
        allocator.destroy(self);
    }
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

    fn check(self: *Parser, tokenType: lexer.TokenType) bool {
        if (self.atEnd()) {
            return false;
        }
        return self.peek().type == tokenType;
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

    fn equality(self: *Parser, allocator: std.mem.Allocator) !*Expr {
        var expr = try self.comparison(allocator);

        while (self.match([_]lexer.TokenType{ .neq, .eq })) {
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

    fn expression(self: *Parser, allocator: std.mem.Allocator) !*Expr {
        return try self.equality(allocator);
    }

    fn primary(self: *Parser, allocator: std.mem.Allocator) !*Expr {
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
        if (self.match([_]lexer.TokenType{ .num_literal, .str_literal })) {
            var expr = try Expr.createLiteral(allocator, self.previous().literal);
            return expr;
        }
        if (self.matchOne(.l_paren)) {}
    }

    fn unaryPre(self: *Parser, allocator: std.mem.Allocator) !*Expr {
        // TODO: unary post-fix
        if (self.match([_]lexer.TokenType{
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

    fn factor(self: *Parser, allocator: std.mem.Allocator) !*Expr {
        var expr = try self.unaryPre(allocator);

        while (self.match([_]lexer.TokenType{
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
            expr = Expr.createBinaryOp(allocator, temp, op, right);
        }
        return expr;
    }

    fn term(self: *Parser, allocator: std.mem.Allocator) !*Expr {
        var expr = try self.factor(allocator);
        while (self.match([_]lexer.TokenType{
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
            expr = Expr.createBinaryOp(allocator, temp, op, right);
        }
        return expr;
    }

    fn comparison(self: *Parser, allocator: std.mem.Allocator) !*Expr {
        var expr = try self.term(allocator);

        while (self.match([_]lexer.TokenType{
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
            expr = Expr.createBinaryOp(allocator, temp, op, right);
        }
        return expr;
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
