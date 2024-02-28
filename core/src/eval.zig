const std = @import("std");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const string_utils = @import("string_utils.zig");

pub const ResolvedValue = union(enum) {
    none: void,
    boolean: bool,
    integer: lexer.int_t,
    float: lexer.float_t,
    string: []const u8,
};

pub const Result = struct {
    value: ResolvedValue,

    pub fn newBoolean(b: bool) Result {
        return Result{ .value = .{
            .boolean = b,
        } };
    }

    pub fn newInteger(i: lexer.int_t) Result {
        return Result{ .value = .{
            .integer = i,
        } };
    }

    pub fn newFloat(f: lexer.float_t) Result {
        return Result{ .value = .{
            .float = f,
        } };
    }

    /// Input string is copied
    pub fn newString(allocator: std.mem.Allocator, str: []const u8) !Result {
        const s = try string_utils.copyString(allocator, str);
        const result = Result{
            .value = .{
                .string = s,
            },
        };
        return result;
    }

    pub fn deinit(self: *Result, allocator: std.mem.Allocator) void {
        switch (self.value) {
            .string => {
                allocator.free(self.value.string);
            },
            else => {},
        }
    }
};

fn evalInts(op: parser.BinaryOp, left_result: Result, right_result: Result) !Result {
    const left = left_result.value.integer;
    const right = right_result.value.integer;
    switch (op) {
        .plus => {
            return Result.newInteger(left + right);
        },
        .minus => {
            return Result.newInteger(left - right);
        },
        .mult => {
            return Result.newInteger(left * right);
        },
        .pow => {
            return Result.newInteger(std.math.pow(lexer.int_t, left, right));
        },
        .eq => {
            return Result.newBoolean(left == right);
        },
        .lt => {
            return Result.newBoolean(left < right);
        },
        .lte => {
            return Result.newBoolean(left <= right);
        },
        .gt => {
            return Result.newBoolean(left > right);
        },
        .gte => {
            return Result.newBoolean(left >= right);
        },
        .neq => {
            return Result.newBoolean(left != right);
        },
        else => {
            return error.InvalidIntBinaryOperator;
        },
    }
}

fn evalFloats(op: parser.BinaryOp, left_result: Result, right_result: Result) !Result {
    const left = left_result.value.float;
    const right = right_result.value.float;
    switch (op) {
        .plus => {
            return Result.newFloat(left + right);
        },
        .minus => {
            return Result.newFloat(left - right);
        },
        .mult => {
            return Result.newFloat(left * right);
        },
        .div => {
            if (right == 0) {
                return error.DivideByZero;
            }
            return Result.newFloat(left / right);
        },
        .pow => {
            return Result.newFloat(std.math.pow(lexer.float_t, left, right));
        },
        .eq => {
            // TODO: use an epsilon
            return Result.newBoolean(left == right);
        },
        .lt => {
            return Result.newBoolean(left < right);
        },
        .lte => {
            return Result.newBoolean(left <= right);
        },
        .gt => {
            return Result.newBoolean(left > right);
        },
        .gte => {
            return Result.newBoolean(left >= right);
        },
        .neq => {
            return Result.newBoolean(left != right);
        },
        else => {
            return error.InvalidFloatBinaryOperator;
        },
    }
}

fn coerceIntToFloat(r: Result) !Result {
    switch (r.value) {
        .integer => {
            return Result.newFloat(@as(lexer.float_t, @floatFromInt(r.value.integer)));
        },
        .float => {
            return r;
        },
        else => {
            return error.InvalidCoercion;
        },
    }
}

pub fn eval(allocator: std.mem.Allocator, expr: *parser.Expr) !Result {
    var result: Result = undefined;
    switch (expr.value.*) {
        .unknown => {
            return error.UnknownExpression;
        },
        .literal => {
            const literal = expr.value.literal;
            switch (literal) {
                .boolean => {
                    result = Result.newBoolean(literal.boolean);
                },
                .integer => {
                    result = Result.newInteger(literal.integer);
                },
                .float => {
                    result = Result.newFloat(literal.float);
                },
                .string => {
                    result = try Result.newString(allocator, literal.string);
                },
                else => {
                    return error.UnhandledLiteral;
                },
            }
        },
        .unary => {
            const unary = expr.value.unary;
            var operand = try eval(allocator, unary.operand);
            defer operand.deinit(allocator);
            switch (unary.op) {
                .neg => {
                    switch (operand.value) {
                        .integer => {
                            result = Result.newInteger(-operand.value.integer);
                        },
                        .float => {
                            result = Result.newFloat(-operand.value.float);
                        },
                        else => {
                            std.log.warn("Negative operand must be float or integer", .{});
                            return error.InvalidNegativeOperand;
                        },
                    }
                },
                .percent => {
                    switch (operand.value) {
                        .integer => {
                            const as_float = @as(lexer.float_t, @floatFromInt(operand.value.integer));
                            result = Result.newFloat(as_float / 100);
                        },
                        .float => {
                            result = Result.newFloat(operand.value.float / 100.0);
                        },
                        else => {
                            std.log.warn("Percent operand must be float or integer", .{});
                            return error.InvalidPercentOperand;
                        },
                    }
                },
                else => {
                    std.log.warn("Unhandled unary operator", .{});
                    return error.UnhandledUnaryOperator;
                },
            }
        },
        .binary => {
            const binary = expr.value.binary;
            var left = try eval(allocator, binary.left);
            defer left.deinit(allocator);
            var right = try eval(allocator, binary.right);
            defer right.deinit(allocator);

            var use_ints = switch (left.value) {
                .integer => switch (right.value) {
                    .integer => true,
                    else => false,
                },
                else => false,
            };
            // Ints are closed under addition, subtraction, and multiplication.
            // But not division.
            const op = binary.op;
            if (op == .div) {
                use_ints = false;
            }
            if (use_ints) {
                result = try evalInts(op, left, right);
            } else {
                var left_float = try coerceIntToFloat(left);
                defer left_float.deinit(allocator);
                var right_float = try coerceIntToFloat(right);
                defer right_float.deinit(allocator);
                result = try evalFloats(op, left_float, right_float);
            }
        },
        else => {
            return error.UnhandledExpression;
        },
    }
    return result;
}

fn testInts(allocator: std.mem.Allocator, source: []const u8, expected: lexer.int_t) !void {
    var tokenizer = lexer.Tokenizer.new(source);
    const tokens = try tokenizer.tokenize(allocator);
    defer {
        for (tokens) |token| {
            var t = token;
            t.deinit(allocator);
        }
        allocator.free(tokens);
    }
    var p = parser.Parser.new(tokens);
    var expr = try p.parse(allocator);
    defer expr.destroySelf(allocator);
    var result = try eval(allocator, expr);
    defer result.deinit(allocator);

    switch (result.value) {
        .integer => {
            try std.testing.expectEqual(expected, result.value.integer);
        },
        else => {
            try std.testing.expect(false);
        },
    }
}

test "integer evaluations" {
    const allocator = std.heap.page_allocator;
    try testInts(allocator, "-2", -2);
    try testInts(allocator, "3 + 4", 7);
}
