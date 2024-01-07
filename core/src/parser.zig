const std = @import("std");
const lexer = @import("lexer.zig");

const NodeType = enum {
    unknown,
    /// or, a leaf
    literal,
    unary,
    binary,
    variadic,
    grouping,
};

/// Not exhaustive, some are context-dependent (e.g. space, minus),
/// which are returned as unknown
fn getNodeType(token_type: lexer.TokenType) NodeType {
    var node_type: NodeType = undefined;
    node_type = switch (token_type) {
        .str_literal, .num_literal, .false, .true, .cell_ref => .literal,
        .ref_op, .pound, .percent => .unary,
        .plus, .mult, .div, .pow, .eq, .lt, .gt, .lte, .gte, .neq, .concat, .range_op => .binary,
        .func_call => .variadic,
        else => .unknown,
    };
    return node_type;
}

/// Node on tree
pub const CellExpr = struct {
    token_type: lexer.TokenType,
    content_str: []const u8,
    children: *std.ArrayListUnmanaged(*Self),

    const Self = @This();

    /// Heap allocation
    pub fn create(allocator: std.mem.Allocator, content_str: []const u8, token_type: lexer.TokenType) !*Self {
        var result = try allocator.create(Self);
        var children = try allocator.create(std.ArrayListUnmanaged(*Self));
        children.* = try std.ArrayListUnmanaged(*Self).initCapacity(allocator, 2);
        result.* = Self{
            .children = children,
            .token_type = token_type,
            .content_str = content_str,
        };
        return result;
    }

    pub fn create_empty(allocator: std.mem.Allocator) !*Self {
        return try Self.create(allocator, "", .unknown);
    }

    /// Also calls destroy on self and descendents
    pub fn destroy(self: *Self, allocator: std.mem.Allocator) void {
        for (self.children.items) |child| {
            child.destroy(allocator);
        }
        self.children.deinit(allocator);
        allocator.destroy(self.children);
        allocator.destroy(self);
    }

    /// caller must free
    pub fn toSexpr(self: Self, allocator: std.mem.Allocator) ![]const u8 {
        var arr = try std.ArrayListUnmanaged(u8).initCapacity(allocator, self.content_str.len);
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

    pub fn addChild(self: *Self, allocator: std.mem.Allocator, child: *Self) !void {
        try self.children.append(allocator, child);
    }

    /// Parses string into Expression tree
    pub fn parse(allocator: std.mem.Allocator, s: []const u8) !*Self {
        var tokenizer = try lexer.Tokenizer.new(allocator, s);
        defer tokenizer.deinit(allocator);

        var token = try tokenizer.next();
        var root = try Self.create_empty(allocator);
        while (token.type != .eof) {
            const node_type = getNodeType(token.type);
            const str = s[token.start..token.end];
            switch (node_type) {
                .literal => {
                    var child = try Self.create(allocator, str, token.type);
                    try root.addChild(allocator, child);
                },
                .unary, .binary, .variadic => {
                    root.content_str = str;
                    root.token_type = token.type;
                },
                else => {
                    // TODO: handle nested and actually everything
                },
            }
            token = try tokenizer.next();
        }
        return root;
    }
};

test "print debug" {
    const allocator = std.testing.allocator;
    var expr = try CellExpr.create(allocator, "+", .plus);
    defer expr.destroy(allocator);
    var left = try CellExpr.create(allocator, "5", .num_literal);
    var right = try CellExpr.create(allocator, "4", .num_literal);
    try expr.addChild(allocator, left);
    try expr.addChild(allocator, right);

    const sexpr = try expr.toSexpr(allocator);
    try std.testing.expectEqualStrings("(+ 5 4)", sexpr);
    defer allocator.free(sexpr);
}

test "parse simple expressions" {
    const allocator = std.testing.allocator;
    var parsed = try CellExpr.parse(allocator, "5+4");
    defer parsed.destroy(allocator);
    try std.testing.expectEqual(lexer.TokenType.plus, parsed.token_type);
    const left = parsed.children.items[0];
    try std.testing.expectEqual(lexer.TokenType.num_literal, left.token_type);
    const right = parsed.children.items[1];
    try std.testing.expectEqualStrings("4", right.content_str);
}
