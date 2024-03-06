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

const Tile3 = []Data;
const Tile2 = []Tile3;
const Tile1 = []Tile2;
const Tile0 = []Tile1;

inline fn compute_index(row: usize, col: usize, remaining_levels: usize) usize {
    return (((col >> (remaining_levels * LOGW)) & MW) << LOGH) | ((row >> (remaining_levels * LOGH)) & MH);
}

/// QT4 is a simplified 4-level quadtree
/// See Spreadsheet Implementation Technology (Sestoft)
/// p. 60
pub const QT4 = struct {
    root: Tile0,

    allocs_tile_1: std.ArrayList(Tile1),
    allocs_tile_2: std.ArrayList(Tile2),
    allocs_tile_3: std.ArrayList(Tile3),

    pub fn new(allocator: std.mem.Allocator) !QT4 {
        const root = try allocator.alloc(Tile1, W * H);
        return QT4{
            .root = root,
            .allocs_tile_1 = try std.ArrayList(Tile1).init(allocator),
            .allocs_tile_2 = try std.ArrayList(Tile2).init(allocator),
            .allocs_tile_3 = try std.ArrayList(Tile3).init(allocator),
        };
    }

    pub fn deinit(self: QT4, allocator: std.mem.Allocator) void {
        for (self.allocs_tile_3.items) |data_slice| {
            allocator.free(data_slice);
        }
        self.allocs_tile_3.deinit();
        for (self.allocs_tile_2.items) |data_slice| {
            allocator.free(data_slice);
        }
        self.allocs_tile_2.deinit();
        for (self.allocs_tile_1.items) |data_slice| {
            allocator.free(data_slice);
        }
        self.allocs_tile_1.deinit();
        allocator.free(self.root);
    }

    pub fn get(self: QT4, row: usize, col: usize) ?Data {
        if (SIZEW <= col or SIZEH <= row) {
            return null;
        }
        const index_1 = compute_index(row, col, 3);
        if (index_1 >= self.root.len) {
            return null;
        }
        const tile_1 = self.root[index_1];
        if (tile_1.len == 0) {
            // TODO: does this check work for an unallocated slice?
            return null;
        }
        const index_2 = compute_index(row, col, 2);
        if (index_2 >= tile_1.len) {
            return null;
        }
        const tile_2 = tile_1[index_2];
        if (tile_2.len == 0) {
            return null;
        }
        const index_3 = compute_index(row, col, 1);
        if (index_3 >= tile_2.len) {
            return null;
        }
        const tile_3 = tile_2[index_3];
        if (tile_3.len == 0) {
            return null;
        }
        const index_4 = compute_index(row, col, 0);
        if (index_4 >= tile_3.len) {
            return null;
        }
        return tile_3[index_4];
    }

    /// Right now, invalid indexes are no-ops
    pub fn set(self: QT4, allocator: std.mem.Allocator, row: usize, col: usize, data: Data) !void {
        if (SIZEW <= col or SIZEH <= row) {
            return;
        }
        const index_1 = compute_index(row, col, 3);
        if (index_1 >= self.root.len) {
            return;
        }
        var tile_1 = self.root[index_1];
        if (tile_1.len == 0) {
            const new_tile_1 = try allocator.alloc(Tile2, W * H);
            self.allocs_tile_1.append(new_tile_1);
            tile_1.* = new_tile_1;
        }
        const index_2 = compute_index(row, col, 2);
        if (index_2 >= tile_1.len) {
            return;
        }
        var tile_2 = tile_1[index_2];
        if (tile_2.len == 0) {
            const new_tile_2 = try allocator.alloc(Tile3, W * H);
            self.allocs_tile_2.append(new_tile_2);
            tile_1[index_2] = new_tile_2;
        }
        const index_3 = compute_index(row, col, 1);
        if (index_3 >= tile_2.len) {
            return;
        }
        const tile_3 = tile_2[index_3];
        if (tile_3.len == 0) {
            const new_tile_3 = try allocator.alloc(Data, W * H);
            self.allocs_tile_3.append(new_tile_3);
            tile_2[index_3] = new_tile_3;
        }
        const index_4 = compute_index(row, col, 0);
        if (index_4 >= tile_3.len) {
            return;
        }
        tile_3[index_4] = data;
    }
};
