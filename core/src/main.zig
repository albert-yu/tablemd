const std = @import("std");
const parser = @import("parser.zig");
const evaluator = @import("eval.zig");
const io = std.io;
const fmt = std.fmt;

const print = std.debug.print;

pub fn main() !void {
    const stdout = io.getStdOut().writer();
    const stdin = io.getStdIn();

    try stdout.print("Spreadsheet. (^D to exit)\n", .{});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();
    var line_buf: [2048]u8 = undefined;
    while (true) {
        try stdout.print("> ", .{});
        const amt = try stdin.read(&line_buf);
        if (amt == 0) {
            // ctrl-d
            break;
        }
        if (amt == line_buf.len) {
            try stdout.print("Input too long.\n", .{});
            continue;
        }
        const line = std.mem.trimRight(u8, line_buf[0..amt], "\r\n");
        if (line.len == 0) {
            continue;
        }
        const expr = parser.parse(allocator, line) catch |err| {
            // TODO: this leaks
            try stdout.print("Parse error: {}\n", .{err});
            continue;
        };
        defer expr.destroySelf(allocator);

        const result = evaluator.eval(allocator, expr) catch |err| {
            // TODO: this leaks
            try stdout.print("Eval error: {}\n", .{err});
            continue;
        };
        const str = try result.toString(allocator);
        defer allocator.free(str);
        try stdout.print("{s}\n", .{str});
    }
}
