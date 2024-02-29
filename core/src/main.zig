const std = @import("std");
const parser = @import("parser.zig");
const print = std.debug.print;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    const expr = try parser.parse(allocator, "SUM(1,2)");
    defer expr.destroySelf(allocator);

    const sexpr = try expr.toAstString(allocator);
    defer allocator.free(sexpr);
    print("Parsed: {s}\n", .{sexpr});
}
