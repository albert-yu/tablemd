const std = @import("std");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const string_utils = @import("string_utils.zig");

pub const ResultValue = union(enum) {
    none: void,
    boolean: bool,
    integer: lexer.int_t,
    float: lexer.float_t,
    string: []const u8,
};

pub const Result = struct {
    value: ResultValue,

    /// If string, it is allocated with the allocator.
    pub fn new(allocator: std.mem.Allocator, value: ResultValue) !Result {
        var result_val: ResultValue = undefined;
        switch (value) {
            .string => {
                const s = try string_utils.copyString(allocator, value.string);
                result_val = .string(s);
            },
            else => result_val = value,
        }
        const result = Result{
            .value = result_val,
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

pub fn eval(expr: *parser.Expr) Result {
    switch (expr.value.*) {
        .unary => {
            const unary = expr.value.unary;
            const operand = eval(unary.operand);
            if (operand.err != null) {
                return .err(operand.err);
            }
            switch (unary.op) {
                .minus => {
                    switch (operand.value) {
                        .integer => return .value(.integer{ .value = -operand.value.integer.value }),
                        .float => return .value(.float{ .value = -operand.value.float.value }),
                        else => unreachable,
                    }
                },
                .not => {
                    switch (operand.value) {
                        .boolean => return .value(.boolean{ .value = !operand.value.boolean }),
                        else => unreachable,
                    }
                },
                else => unreachable,
            }
        },
    }
}
