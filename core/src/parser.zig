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

    pub fn empty(allocator: std.mem.Allocator) !Self {
        var empty_expr = try Self.new(allocator, "", .unknown);
        return empty_expr;
    }

    /// Deeply deinits all descendents
    pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        for (self.children.items) |child| {
            var c = child;
            c.deinit(allocator);
        }
        self.children.deinit(allocator);
    }

    /// caller must free
    pub fn toSexpr(self: Self, allocator: std.mem.Allocator) ![]const u8 {
        var arr = try std.ArrayListUnmanaged(u8).initCapacity(allocator, self.content_str.len + 2);
        defer arr.deinit(allocator);

        const has_children = self.children.items.len > 0;
        if (has_children) {
            try arr.append(allocator, '(');
        }
        for (self.content_str) |char| {
            try arr.append(allocator, char);
        }
        for (self.children.items) |child| {
            try arr.append(allocator, ' ');
            const sexpr = try child.toSexpr(allocator);
            defer allocator.free(sexpr);
            for (sexpr) |char| {
                try arr.append(allocator, char);
            }
        }
        if (has_children) {
            try arr.append(allocator, ')');
        }
        return arr.toOwnedSlice(allocator);
    }

    pub fn addChild(self: *Self, allocator: std.mem.Allocator, child: Self) !void {
        try self.children.append(allocator, child);
    }

    /// Parses string into Expression tree
    pub fn parse(allocator: std.mem.Allocator, s: []const u8) !Self {
        var tokenizer = try lexer.Tokenizer.new(allocator, s);
        defer tokenizer.deinit(allocator);

        var token = try tokenizer.next();
        var root = try Self.empty(allocator);
        while (token.type != .eof) {
            // TODO: handle nested
            token = try tokenizer.next();
        }
        return root;
    }
};

test "print debug" {
    const allocator = std.testing.allocator;
    var expr = try CellExpr.new(allocator, "+", .plus);
    defer expr.deinit(allocator);
    var left = try CellExpr.new(allocator, "5", .num_literal);
    var right = try CellExpr.new(allocator, "4", .num_literal);
    try expr.addChild(allocator, left);
    try expr.addChild(allocator, right);

    const sexpr = try expr.toSexpr(allocator);
    defer allocator.free(sexpr);
    try std.testing.expectEqualStrings("(+ 5 4)", sexpr);
}

test "parse simple expressions" {
    const allocator = std.testing.allocator;
    var parsed = try CellExpr.parse(allocator, "5+4");
    defer parsed.deinit(allocator);
    try std.testing.expectEqual(lexer.TokenType.plus, parsed.token_type);
}
