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

// Cell[][][][] tile0 = new Cell[W * H]

const Data = struct {
    raw: []const u8,
    parsed: *parser.Expr,
};

inline fn compute_index(row: usize, col: usize, remaining_levels: usize) usize {
    return (((col >> (remaining_levels * LOGW)) & MW) << LOGH) | ((row >> (remaining_levels * LOGH)) & MH);
}

/// Assumes T is nullable
fn allocateTile(comptime T: type, allocator: std.mem.Allocator) ![]T {
    const tile = try allocator.alloc(T, W * H);
    for (tile, 0..) |_, i| {
        tile[i] = null;
    }
    return tile;
}

/// QT4 is a simplified 4-level quadtree
/// See Spreadsheet Implementation Technology (Sestoft)
/// p. 60
pub fn QT4(comptime T: type) type {
    return struct {
        root: []?[]?[]?[]T,
        allocs_tile_1: std.ArrayList(?[]?[]?[]T),
        allocs_tile_2: std.ArrayList(?[]?[]T),
        allocs_tile_3: std.ArrayList(?[]T),

        const Self = @This();
        pub fn new(allocator: std.mem.Allocator) !Self {
            const root = try allocateTile(?[]?[]?[]T, allocator);
            return Self{
                .root = root,
                .allocs_tile_1 = try std.ArrayList(?[]?[]?[]T).initCapacity(allocator, 0),
                .allocs_tile_2 = try std.ArrayList(?[]?[]T).initCapacity(allocator, 0),
                .allocs_tile_3 = try std.ArrayList(?[]T).initCapacity(allocator, 0),
            };
        }

        pub fn deinit(self: Self, allocator: std.mem.Allocator) void {
            for (self.allocs_tile_3.items) |maybe_slice| {
                if (maybe_slice) |slice| {
                    allocator.free(slice);
                }
            }
            self.allocs_tile_3.deinit();
            for (self.allocs_tile_2.items) |maybe_slice| {
                if (maybe_slice) |slice| {
                    allocator.free(slice);
                }
            }
            self.allocs_tile_2.deinit();
            for (self.allocs_tile_1.items) |maybe_slice| {
                if (maybe_slice) |slice| {
                    allocator.free(slice);
                }
            }
            self.allocs_tile_1.deinit();
            allocator.free(self.root);
        }

        pub fn get(self: Self, row: usize, col: usize) ?T {
            if (SIZEW <= col or SIZEH <= row) {
                return null;
            }
            const index_1 = compute_index(row, col, 3);
            if (index_1 >= self.root.len) {
                return null;
            }
            const maybe_tile_1 = self.root[index_1];
            if (maybe_tile_1) |tile_1| {
                const index_2 = compute_index(row, col, 2);
                if (index_2 >= tile_1.len) {
                    return null;
                }
                const maybe_tile_2 = tile_1[index_2];
                if (maybe_tile_2) |tile_2| {
                    const index_3 = compute_index(row, col, 1);
                    if (index_3 >= tile_2.len) {
                        return null;
                    }
                    const maybe_tile_3 = tile_2[index_3];
                    if (maybe_tile_3) |tile_3| {
                        const index_4 = compute_index(row, col, 0);
                        if (index_4 >= tile_3.len) {
                            return null;
                        }
                        return tile_3[index_4];
                    }
                }
            }
            return null;
        }

        /// Right now, invalid indexes are no-ops
        pub fn set(self: *Self, allocator: std.mem.Allocator, row: usize, col: usize, data: T) !void {
            if (SIZEW <= col or SIZEH <= row) {
                return;
            }
            const index_1 = compute_index(row, col, 3);
            if (index_1 >= self.root.len) {
                return;
            }
            var tile_1: []?[]?[]T = undefined;
            var maybe_tile_1 = self.root[index_1];
            if (maybe_tile_1) |tile| {
                tile_1 = tile;
            } else {
                tile_1 = try allocateTile(?[]?[]T, allocator);
                try self.allocs_tile_1.append(tile_1);
                self.root[index_1] = tile_1;
            }
            const index_2 = compute_index(row, col, 2);
            if (index_2 >= tile_1.len) {
                return;
            }
            var tile_2: []?[]T = undefined;
            var maybe_tile_2 = tile_1[index_2];
            if (maybe_tile_2) |tile| {
                tile_2 = tile;
            } else {
                tile_2 = try allocateTile(?[]T, allocator);
                try self.allocs_tile_2.append(tile_2);
                tile_1[index_2] = tile_2;
            }
            const index_3 = compute_index(row, col, 1);
            if (index_3 >= tile_2.len) {
                return;
            }
            var tile_3: []T = undefined;
            const maybe_tile_3 = tile_2[index_3];
            if (maybe_tile_3) |tile| {
                tile_3 = tile;
            } else {
                tile_3 = try allocator.alloc(T, W * H);
                try self.allocs_tile_3.append(tile_3);
                tile_2[index_3] = tile_3;
            }
            const index_4 = compute_index(row, col, 0);
            if (index_4 >= tile_3.len) {
                return;
            }
            tile_3[index_4] = data;
        }
    };
}

pub const Map = QT4(Data);

const TestQT4 = QT4(i32);

test "QT4 get and set" {
    var allocator = std.testing.allocator;
    var tree = try TestQT4.new(allocator);
    defer tree.deinit(allocator);

    try tree.set(allocator, 0, 0, 1);
    try tree.set(allocator, 0, 1, 2);
    try tree.set(allocator, 1, 0, 3);

    try std.testing.expectEqual(tree.get(0, 0), 1);
    try std.testing.expectEqual(tree.get(0, 1), 2);
    try std.testing.expectEqual(tree.get(1, 0), 3);
}
