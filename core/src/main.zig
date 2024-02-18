const std = @import("std");
const parser = @import("parser.zig");
const print = std.debug.print;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    //var parsed = try parser.ExprOld.parse(allocator, "$A3=TRUE");
    //defer parsed.destroySelf(allocator);
    //const sexpr = try parsed.toSexpr(allocator);
    //defer allocator.free(sexpr);
    // print("Parsed: {s}\n", .{sexpr});
    var four = try parser.Expr.createLiteral(allocator, .{
        .integer = 4,
    });
    var five = try parser.Expr.createLiteral(allocator, .{
        .integer = 5,
    });
    var expr = try parser.Expr.createBinaryOp(allocator, five, .plus, four);
    defer expr.destroySelf(allocator);

    const sexpr = try expr.toAstString(allocator);
    defer allocator.free(sexpr);

    print("Parsed: {s}\n", .{sexpr});
}
