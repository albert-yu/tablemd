const std = @import("std");
const parse = @import("parser.zig");
const lexer = @import("lexer.zig");
const print = std.debug.print;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    var tokenizer = lexer.Tokenizer.new("2 - 4");
    const tokens = try tokenizer.tokenize(allocator);
    defer {
        for (tokens) |token| {
            var t = token; // discard const
            t.deinit(allocator);
        }
        allocator.free(tokens);
    }

    var parser = parse.Parser.new(tokens);
    const expr = try parser.parse(allocator);
    defer expr.destroySelf(allocator);

    const sexpr = try expr.toAstString(allocator);
    defer allocator.free(sexpr);
    print("Parsed: {s}\n", .{sexpr});
}
