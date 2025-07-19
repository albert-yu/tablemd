const std = @import("std");
const ArrayList = std.ArrayListUnmanaged;
const Allocator = std.mem.Allocator;
const grid = @import("render/dot_grid.zig");

const Size2D = grid.Size2D;

pub const Position = struct {
    left: usize,
    top: usize,
};

pub const TextPosition = struct {
    left: usize,
    top: usize,
    char_offset: usize,
};

const Cell = struct {
    value: []const u8,

    pub fn size(self: Cell, units: Size2D) Size2D {
        var height = 0.0;
        var width = 0.0;
        var curr_line_width = 0.0;
        for (self.value) |char| {
            if (char == '\n') {
                width = @max(width, curr_line_width);
                curr_line_width = 0.0;
                height += units.height;
                continue;
            }
            curr_line_width += units.width;
        }
        return .{ .width = width, .height = height };
    }
};

const Column = struct {
    data: ArrayList(Cell),
    allocator: Allocator,

    pub fn init(allocator: Allocator) Column {
        return Column{
            .data = ArrayList(Cell).initCapacity(allocator, 0) catch unreachable,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Column) void {
        self.data.deinit(self.allocator);
    }

    pub fn size(self: *Column, text_units: Size2D) Size2D {
        var width = 0;
        var height = 0;
        for (self.data.items) |cell| {
            const cell_dims = cell.size(text_units);
            width = @max(width, cell_dims.width);
            height += cell_dims.height;
        }
        return .{ .width = width, .height = height };
    }
};

pub const Table = struct {
    position: Position,
    columns: ArrayList(Column),
    allocator: Allocator,

    pub fn init(allocator: Allocator) Table {
        return Table{
            .position = .{ .left = 0, .top = 0 },
            .columns = ArrayList(Column).initCapacity(allocator, 0) catch unreachable,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Table) void {
        for (self.columns.items) |column| {
            column.deinit();
        }
        self.columns.deinit(self.allocator);
    }

    pub fn size(self: *Table, text_units: Size2D) Size2D {
        var width = 0;
        var height = 0;
        for (self.columns.items) |column| {
            const column_dims = column.size(text_units);
            width += column_dims.width;
            height += column_dims.height;
        }
        return .{ .width = width, .height = height };
    }
};
