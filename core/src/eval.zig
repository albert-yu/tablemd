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
        else => {
            return error.UnhandledExpression;
        },
    }
    return result;
}

test "simple evaluations" {
    const allocator = std.heap.page_allocator;
    const source = "-2";
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
            const expected: lexer.int_t = -2;
            try std.testing.expectEqual(expected, result.value.integer);
        },
        else => {
            try std.testing.expect(false);
        },
    }
}
