const lexer = @import("lexer.zig");
const parser = @import("parser.zig");

pub const ResultValue = union(enum) {
    none: void,
    boolean: bool,
    integer: lexer.int_t,
    float: lexer.float_t,
    string: []const u8,
};

pub const Result = union(enum) {
    value: *ResultValue,
    err: []const u8,
};

pub fn eval(expr: *parser.Expr) Result {
    switch (expr.value) {}
}
