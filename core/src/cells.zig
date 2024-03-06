const std = @import("std");
const parser = @import("parser.zig");

const LOGW = 4;
const LOGH = 5;
const W = 1 << LOGW; // 16
const H = 1 << LOGH; // 32
const MW = W - 1; // 15
const MH = H - 1; // 31
const SIZEW = 1 << (4 * LOGW); // 65536
const SIZEH = 1 << (4 * LOGH); // 1048576

// private readonly Cell[][][][] tile0 = new Cell[W * H]

const Data = struct {
    raw: []const u8,
    parsed: *parser.Expr,
};

const TreeNode = union(enum) {
    /// leaf
    data: Data,

    /// size W * H
    children: ?[]*TreeNode,
};

/// QT4 is a simplified 4-level quadtree
/// See Spreadsheet Implementation Technology (Sestoft)
/// p. 60
pub const Map = struct {
    root: *TreeNode,

    pub fn new(allocator: std.mem.Allocator) !Map {
        const root = try allocator.create(TreeNode);
        const children = try allocator.alloc(*TreeNode, W * H);
        root.* = TreeNode{
            .children = children,
        };
        return Map{
            .root = root,
        };
    }

    pub fn deinit(self: Map, allocator: std.mem.Allocator) void {
        allocator.destroy(self.tree.root);
    }

    // pub fn get(self: Map, row: usize, col: usize) ?Data {
    //     if (SIZEW <= col or SIZEH <= row) {
    //         return null;
    //     }
    // }
};
