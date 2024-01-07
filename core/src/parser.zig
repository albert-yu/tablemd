const std = @import("std");
const lexer = @import("lexer.zig");

/// Node on tree
pub const CellExpr = struct {
    token_type: lexer.TokenType,
    content_str: []const u8,
    children: std.ArrayListUnmanaged(Self),

    const Self = @This();

    pub fn new(allocator: std.mem.Allocator, content_str: []const u8, token_type: lexer.TokenType) !Self {
        var children = try std.ArrayListUnmanaged(Self).initCapacity(allocator, 2);
        return Self{
            .token_type = token_type,
            .content_str = content_str,
            .children = children,
        };
    }

    pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        for (self.children.items) |child| {
            child.deinit(allocator);
        }
        self.children.deinit(allocator);
    }

    pub fn addChild(self: *Self, allocator: std.mem.Allocator, child: Self) !void {
        try self.children.append(allocator, child);
    }

    /// Parses string into Expression tree
    pub fn parse(allocator: std.mem.Allocator, s: []const u8) !Self {
        var tokenizer = try lexer.Tokenizer.new(allocator, s);
        defer tokenizer.deinit(allocator);

        var token = try tokenizer.next();
        while (token.type != .eof) {
            // TODO: handle nested
            token = try tokenizer.next();
        }
    }
};

test "parse simple expressions" {
    const allocator = std.testing.allocator;
    var parsed = try CellExpr.parse(allocator, "5+4");
    defer parsed.deinit(allocator);
    std.testing.expectEqual(lexer.TokenType.plus, parsed.token_type);
}
