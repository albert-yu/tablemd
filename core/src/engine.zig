const std = @import("std");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const string_utils = @import("string_utils.zig");
const map = @import("map.zig");

pub const Result = union(enum) {
    none: void,
    boolean: bool,
    integer: lexer.int_t,
    float: lexer.float_t,
    string: []const u8,

    pub fn newNone() Result {
        return .{ .none = undefined };
    }

    pub fn newBoolean(b: bool) Result {
        return .{
            .boolean = b,
        };
    }

    pub fn newInteger(i: lexer.int_t) Result {
        return .{
            .integer = i,
        };
    }

    pub fn newFloat(f: lexer.float_t) Result {
        return .{
            .float = f,
        };
    }

    /// Input string is copied
    pub fn newString(allocator: std.mem.Allocator, str: []const u8) !Result {
        const s = try string_utils.copyString(allocator, str);
        const result = Result{
            .string = s,
        };
        return result;
    }

    pub fn deinit(self: Result, allocator: std.mem.Allocator) void {
        switch (self) {
            .string => {
                allocator.free(self.string);
            },
            else => {},
        }
    }

    pub fn toString(self: Result, allocator: std.mem.Allocator) ![]const u8 {
        var string_builder = std.ArrayList(u8).init(allocator);
        switch (self) {
            .none => {
                try string_builder.appendSlice("NONE");
            },
            .boolean => {
                if (self.boolean) {
                    try string_builder.appendSlice("TRUE");
                } else {
                    try string_builder.appendSlice("FALSE");
                }
            },
            .integer => {
                const str = try std.fmt.allocPrint(allocator, "{d}", .{self.integer});
                defer allocator.free(str);
                try string_builder.appendSlice(str);
            },
            .float => {
                const str = try std.fmt.allocPrint(allocator, "{d}", .{self.float});
                defer allocator.free(str);
                try string_builder.appendSlice(str);
            },
            .string => {
                try string_builder.append('"');
                for (self.string) |c| {
                    if (c == '"') {
                        // escape double quotes
                        try string_builder.append('\\');
                    }
                    try string_builder.append(c);
                }
                try string_builder.append('"');
            },
        }
        return try string_builder.toOwnedSlice();
    }
};

fn evalInts(op: parser.BinaryOp, left_result: Result, right_result: Result) !Result {
    const left = left_result.integer;
    const right = right_result.integer;
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
    const left = left_result.float;
    const right = right_result.float;
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
    switch (r) {
        .integer => {
            return Result.newFloat(@as(lexer.float_t, @floatFromInt(r.integer)));
        },
        .float => {
            return r;
        },
        else => {
            return error.InvalidCoercion;
        },
    }
}

const BuiltInFunc = enum {
    sum,
    avg,
    product,
};

const func_lookup = std.ComptimeStringMap(BuiltInFunc, .{
    .{ "SUM", .sum },
    .{ "AVG", .avg },
    .{ "PRODUCT", .product },
});

const NumericResult = union(enum) {
    integers: []lexer.int_t,
    floats: []lexer.float_t,

    pub fn deinit(self: NumericResult, allocator: std.mem.Allocator) void {
        switch (self) {
            .integers => allocator.free(self.integers),
            .floats => allocator.free(self.floats),
        }
    }
};

const CellValue = union(enum) {
    none: void,
    res: Result,
    err: []const u8,

    pub fn makeError(allocator: std.mem.Allocator, err: []const u8) !CellValue {
        var err_slice = try allocator.alloc(u8, err.len);
        @memcpy(err_slice, err);
        return .{ .err = err_slice };
    }

    pub fn makeValue(res: Result) CellValue {
        return .{ .res = res };
    }

    pub fn toString(self: CellValue, allocator: std.mem.Allocator) ![]const u8 {
        switch (self) {
            .none => {
                const none = "none";
                const result = try allocator.alloc(u8, none.len);
                @memcpy(result, none);
                return result;
            },
            .res => {
                const result = try self.res.toString(allocator);
                return result;
            },
            .err => return self.err,
        }
    }

    pub fn deinit(self: *CellValue, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .none => {},
            .res => self.res.deinit(allocator),
            .err => allocator.free(self.err),
        }
    }
};

const Map = map.QT4(*Cell);

pub const Cell = struct {
    raw: []const u8,
    val: CellValue,
    map: *Map,

    // TODO: support_graph

    /// IMPORTANT: cell_map is NOT owned by the cell,
    /// so the caller must free it.
    pub fn new(raw: []const u8, cell_map: *Map) Cell {
        return Cell{
            .raw = raw,
            .val = CellValue.none,
            .map = cell_map,
        };
    }

    pub fn deinit(self: *Cell, allocator: std.mem.Allocator) void {
        self.val.deinit(allocator);
    }

    fn evalNumericArgs(self: Cell, allocator: std.mem.Allocator, args: []const *parser.Expr) anyerror!NumericResult {
        var arg_list = try std.ArrayListUnmanaged(*Result).initCapacity(allocator, 1);
        defer arg_list.deinit(allocator);
        var use_float = false;

        // evaluate all the numbers and store them in a list
        for (args) |arg| {
            const r = try self.evalExpr(allocator, arg);
            const allocated = try allocator.create(Result);
            allocated.* = r;
            try arg_list.append(allocator, allocated);
            switch (r) {
                .integer => {},
                .float => {
                    use_float = true;
                },
                else => return error.InvalidNumericArgument,
            }
        }
        defer {
            for (arg_list.items) |r| {
                r.deinit(allocator);
                allocator.destroy(r);
            }
        }

        // convert list to a NumericResult
        var result: NumericResult = undefined;
        if (use_float) {
            result = NumericResult{
                .floats = try allocator.alloc(lexer.float_t, arg_list.items.len),
            };
            for (arg_list.items, 0..) |r, i| {
                switch (r.*) {
                    .integer => {
                        result.floats[i] = @as(lexer.float_t, @floatFromInt(r.integer));
                    },
                    .float => {
                        result.floats[i] = r.float;
                    },
                    else => unreachable,
                }
            }
        } else {
            result = NumericResult{
                .integers = try allocator.alloc(lexer.int_t, arg_list.items.len),
            };
            for (arg_list.items, 0..) |r, i| {
                result.integers[i] = r.integer;
            }
        }
        return result;
    }

    fn evalFunc(self: Cell, allocator: std.mem.Allocator, name: []const u8, args: []const *parser.Expr) anyerror!Result {
        const func = func_lookup.get(name);
        if (func) |f| {
            switch (f) {
                .sum => {
                    const num_args = try self.evalNumericArgs(allocator, args);
                    defer num_args.deinit(allocator);

                    switch (num_args) {
                        .integers => {
                            var sum: lexer.int_t = 0;
                            for (num_args.integers) |arg| {
                                sum += arg;
                            }
                            return Result.newInteger(sum);
                        },
                        .floats => {
                            var sum: lexer.float_t = 0;
                            for (num_args.floats) |arg| {
                                sum += arg;
                            }
                            return Result.newFloat(sum);
                        },
                    }
                },
                .avg => {
                    const args_evaluated = try self.evalNumericArgs(allocator, args);
                    defer args_evaluated.deinit(allocator);
                    var sum: lexer.float_t = 0;
                    var count: lexer.float_t = 0;
                    switch (args_evaluated) {
                        .integers => {
                            var int_sum: lexer.int_t = 0;
                            for (args_evaluated.integers) |arg| {
                                int_sum += arg;
                            }
                            count = @as(lexer.float_t, @floatFromInt(args_evaluated.integers.len));
                            sum = @as(lexer.float_t, @floatFromInt(int_sum));
                        },
                        .floats => {
                            for (args_evaluated.floats) |arg| {
                                sum += arg;
                            }
                            count = @as(lexer.float_t, @floatFromInt(args_evaluated.integers.len));
                        },
                    }
                    return Result.newFloat(sum / count);
                },
                .product => {
                    const num_args = try self.evalNumericArgs(allocator, args);
                    defer num_args.deinit(allocator);
                    switch (num_args) {
                        .integers => {
                            var product: lexer.int_t = 1;
                            for (num_args.integers) |arg| {
                                product *= arg;
                            }
                            return Result.newInteger(product);
                        },
                        .floats => {
                            var product: lexer.float_t = 1;
                            for (num_args.floats) |arg| {
                                product *= arg;
                            }
                            return Result.newFloat(product);
                        },
                    }
                },
            }
        } else {
            return error.UnknownFunction;
        }
    }

    pub fn evalExpr(self: Cell, allocator: std.mem.Allocator, expr: *parser.Expr) anyerror!Result {
        var result: Result = undefined;
        switch (expr.*) {
            .unknown => {
                return error.UnknownExpression;
            },
            .literal => {
                const literal = expr.literal;
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
                    .cell_ref => {
                        const row = literal.cell_ref.row;
                        const col = literal.cell_ref.col;
                        var maybe_cell: ?*Cell = self.map.get(row, col);
                        if (maybe_cell) |cell| {
                            var res = try cell.evalSelf(allocator);
                            switch (res) {
                                .none => return error.CellHasNoValue,
                                else => {
                                    result = res;
                                },
                            }
                        } else {
                            return error.MissingCellReference;
                        }
                    },
                    else => {
                        return error.UnhandledLiteral;
                    },
                }
            },
            .unary => {
                const unary = expr.unary;
                var operand = try self.evalExpr(allocator, unary.operand);
                defer operand.deinit(allocator);
                switch (unary.op) {
                    .neg => {
                        switch (operand) {
                            .integer => {
                                result = Result.newInteger(-operand.integer);
                            },
                            .float => {
                                result = Result.newFloat(-operand.float);
                            },
                            else => {
                                std.log.warn("Negative operand must be float or integer", .{});
                                return error.InvalidNegativeOperand;
                            },
                        }
                    },
                    .percent => {
                        switch (operand) {
                            .integer => {
                                const as_float = @as(lexer.float_t, @floatFromInt(operand.integer));
                                result = Result.newFloat(as_float / 100);
                            },
                            .float => {
                                result = Result.newFloat(operand.float / 100.0);
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
                const binary = expr.binary;
                var left = try self.evalExpr(allocator, binary.left);
                defer left.deinit(allocator);
                var right = try self.evalExpr(allocator, binary.right);
                defer right.deinit(allocator);

                var use_ints = switch (left) {
                    .integer => switch (right) {
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
            .variadic => {
                const variadic = expr.variadic;
                result = try self.evalFunc(allocator, variadic.func, variadic.args);
            },
            .grouping => {
                result = try self.evalExpr(allocator, expr.grouping.operand);
            },
        }
        return result;
    }

    /// Evaluates the cell's expression and stores the result in the cell.
    /// Also returns the result.
    /// Run-time errors are caught and stored in the cell.
    pub fn evalSelf(self: *Cell, allocator: std.mem.Allocator) !Result {
        if (self.raw.len == 0) {
            // empty cell is no-op
            return Result.newNone();
        }
        var expr = parser.parse(allocator, self.raw) catch |err| {
            std.log.warn("Failed to parse cell: {}", .{err});
            self.val = try CellValue.makeError(allocator, "Failed to parse cell");
            return Result.newNone();
        };
        defer expr.destroySelf(allocator);
        var result = self.evalExpr(allocator, expr) catch |eval_err| {
            std.log.warn("Failed to evaluate cell: {}", .{eval_err});
            self.val = try CellValue.makeError(allocator, "Failed to evaluate cell");
            return Result.newNone();
        };
        // clear old value
        self.val.deinit(allocator);
        self.val = CellValue.makeValue(result);

        return result;

        // TODO: for each cell in support_graph
    }
};

pub const Sheet = struct {
    map: Map,

    pub fn new(allocator: std.mem.Allocator) !Sheet {
        var cell_map = try Map.new(allocator);
        return .{
            .map = cell_map,
        };
    }

    pub fn deinit(self: *Sheet, allocator: std.mem.Allocator) void {
        self.map.deinit(allocator);
    }

    pub fn eval(self: *Sheet, allocator: std.mem.Allocator, source: []const u8) !Result {
        var cell = Cell.new(source, &self.map);
        defer cell.deinit(allocator);
        return cell.evalSelf(allocator);
    }
};

fn testEval(allocator: std.mem.Allocator, source: []const u8, comptime T: type, expected: T, val_getter: fn (Result) error{ValueError}!T) !void {
    var sheet = try Sheet.new(allocator);
    defer sheet.deinit(allocator);
    var result = try sheet.eval(allocator, source);
    defer result.deinit(allocator);

    var result_value = try val_getter(result);
    try std.testing.expectEqual(expected, result_value);
}

fn getIntVal(r: Result) error{ValueError}!lexer.int_t {
    switch (r) {
        .integer => return r.integer,
        else => return error.ValueError,
    }
}

fn getFloatVal(r: Result) error{ValueError}!lexer.float_t {
    switch (r) {
        .float => return r.float,
        else => return error.ValueError,
    }
}

fn testInts(allocator: std.mem.Allocator, source: []const u8, expected: lexer.int_t) !void {
    try testEval(allocator, source, lexer.int_t, expected, getIntVal);
}

fn testFloats(allocator: std.mem.Allocator, source: []const u8, expected: lexer.float_t) !void {
    try testEval(allocator, source, lexer.float_t, expected, getFloatVal);
}

test "integer evaluations" {
    const allocator = std.heap.page_allocator;
    try testInts(allocator, "-2", -2);
    try testInts(allocator, "3 + 4", 7);
    try testInts(allocator, "9 * 7", 63);
    try testInts(allocator, "12*12", 144);
    try testInts(allocator, "3^2", 9);
    try testFloats(allocator, "12 / 2", 6);
    try testFloats(allocator, "1 / 2", 0.5);
}

test "float evaluations" {
    const allocator = std.heap.page_allocator;
    try testFloats(allocator, "-2.0", -2.0);
    try testFloats(allocator, "3.0 + 4.0", 7.0);
    try testFloats(allocator, "SUM(1, 2, 3.5)", 6.5);
}

test "precedence" {
    const allocator = std.heap.page_allocator;
    try testInts(allocator, "3 + 4 * 5", 23);
    try testInts(allocator, "3 * 4 + 5", 17);
    try testInts(allocator, "3 * (4 + 5)", 27);
    try testInts(allocator, "3 * (4 + 5) * 2", 54);
    try testInts(allocator, "3 * (4 + 5) * 2 + 1", 55);
    try testInts(allocator, "3 * (4 + 5) * (2 + 1)", 81);
}
