const std = @import("std");
const re = @import("regex.zig");
const print = std.debug.print;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    const regex = try re.Regex.new(allocator, "hello ?([[:alpha:]]*)");
    defer regex.destroy(allocator);
    const input = "hello Teg!";
    const matches = try regex.eval(allocator, input);
    defer allocator.free(matches);
    for (matches, 0..) |m, i| {
        const match = input[m.start..m.end];
        print("matches[{d}] = {s}\n", .{ i, match });
    }
}

test "simple test" {
    const allocator = std.testing.allocator;
    const regex = try re.Regex.new(allocator, "hello ?([[:alpha:]]*)");
    defer regex.destroy(allocator);
    const input = "hello Teg!";
    const matches = try regex.eval(allocator, input);
    defer allocator.free(matches);
    const expected: usize = 2;
    try std.testing.expectEqual(expected, matches.len);
}
