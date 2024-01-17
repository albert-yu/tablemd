const std = @import("std");
const parser = @import("parser.zig");
const print = std.debug.print;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    var parsed = try parser.CellExpr.parse(allocator, "$A3=TRUE");
    defer parsed.destroy(allocator);
    const sexpr = try parsed.toSexpr(allocator);
    defer allocator.free(sexpr);
    print("Parsed: {s}\n", .{sexpr});
}
