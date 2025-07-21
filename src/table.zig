const std = @import("std");
const ArrayList = std.ArrayListUnmanaged;
const Allocator = std.mem.Allocator;
const grid = @import("render/dot_grid.zig");
const scene_mod = @import("render/scene.zig");
const Vec2 = @import("zm").Vec2f;

const Scene = scene_mod.Scene;
const Size = grid.Size;

pub const Units = struct {
    cell: Size,
    text: Size,
};

pub const GridPos = struct {
    left: usize = 0,
    top: usize = 0,
};

pub const GridSize = struct {
    width: usize = 0,
    height: usize = 0,
};

pub const Direction = enum {
    none,
    left,
    right,
    up,
    down,
};

pub const MatchingCol = struct {
    index: usize,
    /// Grid position of the left of the column
    left: usize,
    width: usize,
};

pub const MatchingRow = struct {
    index: usize,
    /// Grid position of the top of the row
    top: usize,
    height: usize,
};

pub const Cell = struct {
    value: ArrayList(u8),
    column: *Column,

    pub fn init(allocator: Allocator, content: []const u8, column: *Column) !Cell {
        var value = try ArrayList(u8).initCapacity(allocator, content.len);
        value.appendSlice(allocator, content) catch unreachable;
        return Cell{ .value = value, .column = column };
    }

    pub fn deinit(self: *Cell, allocator: Allocator) void {
        self.value.deinit(allocator);
    }

    pub fn gridSize(self: Cell, units: Units) GridSize {
        const cell_units = units.cell;
        const text_units = units.text;

        var grid_height: usize = 1;
        var width: f32 = 0.0;
        var curr_line_width: f32 = 0.0;
        for (self.value.items) |char| {
            if (char == '\n') {
                width = @max(width, curr_line_width);
                curr_line_width = 0.0;
                grid_height += 1;
                continue;
            }
            curr_line_width += text_units.width;
        }
        width = @max(width, curr_line_width);
        const container_width = divCeil(width, cell_units.width);
        return .{ .width = @intFromFloat(container_width), .height = grid_height };
    }

    pub fn size(self: Cell, units: Units) Size {
        const grid_size = self.gridSize(units);
        return Size{
            .width = @as(f32, @floatFromInt(grid_size.width)) * units.cell.width,
            .height = @as(f32, @floatFromInt(grid_size.height)) * units.cell.height,
        };
    }

    pub fn addSelfToScene(self: Cell, scene: *Scene, allocator: Allocator, units: Units, position: Vec2) !void {
        // This is addition is here because otherwise, the
        // text starts above the first row. Reason being that
        // the text bearing_y is negative and pulls the text
        // upwards
        var pos_y = position[1] + units.cell.height;
        var i: usize = 0;
        var start: usize = i;
        while (i < self.value.items.len) : (i += 1) {
            const char = self.value.items[i];
            if (char == '\n') {
                // send the current line to the scene
                try scene.texts.append(allocator, .{
                    .text = self.value.items[start..i],
                    .x = position[0],
                    .y = pos_y,
                });
                i += 1; // skip the newline
                start = i;
                pos_y += units.text.height;
                continue;
            }
        }
        if (start < self.value.items.len) {
            try scene.texts.append(allocator, .{
                .text = self.value.items[start..self.value.items.len],
                .x = position[0],
                .y = pos_y,
            });
        }
    }
};

pub fn divCeil(top: f32, bottom: f32) f32 {
    const exact = top / bottom;
    return @ceil(exact);
}

pub const Column = struct {
    data: ArrayList(Cell),
    table: *Table,

    pub fn init(allocator: Allocator, table: *Table) Column {
        return Column{
            .data = ArrayList(Cell).initCapacity(allocator, 0) catch unreachable,
            .table = table,
        };
    }

    pub fn deinit(self: *Column, allocator: Allocator) void {
        for (self.data.items) |*cell| {
            cell.deinit(allocator);
        }
        self.data.deinit(allocator);
    }

    pub fn addCell(self: *Column, allocator: Allocator, content: []const u8) !void {
        const cell = try Cell.init(allocator, content, self);
        try self.data.append(allocator, cell);
    }

    pub fn gridSize(self: Column, units: Units) GridSize {
        var width: usize = 0;
        var height: usize = 0;
        for (self.data.items) |cell| {
            const cell_dims = cell.gridSize(units);
            width = @max(width, cell_dims.width);
            height += cell_dims.height;
        }
        return .{ .width = width, .height = height };
    }

    pub fn size(self: Column, units: Units) Size {
        const grid_size = self.gridSize(units);
        return Size{
            .width = @as(f32, @floatFromInt(grid_size.width)) * units.cell.width,
            .height = @as(f32, @floatFromInt(grid_size.height)) * units.cell.height,
        };
    }

    pub fn addSelfToScene(self: Column, scene: *Scene, allocator: Allocator, units: Units, position: Vec2) !void {
        var pos_y = position[1];
        for (self.data.items) |cell| {
            const cell_dims = cell.size(units);
            try cell.addSelfToScene(scene, allocator, units, Vec2{ position[0], pos_y });
            pos_y += cell_dims.height;
        }
    }
};

pub const Table = struct {
    position: GridPos,
    /// All columns are enforced to have the same number of rows
    columns: ArrayList(*Column),

    pub fn init(allocator: Allocator) Table {
        return Table{
            .position = .{ .left = 0, .top = 0 },
            .columns = ArrayList(*Column).initCapacity(allocator, 0) catch unreachable,
        };
    }

    pub fn deinit(self: *Table, allocator: Allocator) void {
        for (self.columns.items) |column| {
            column.deinit(allocator);
            allocator.destroy(column);
        }
        self.columns.deinit(allocator);
    }

    pub fn rows(self: Table) usize {
        if (self.columns.items.len == 0) {
            return 0;
        }
        return self.columns.items[0].data.items.len;
    }

    pub fn cols(self: Table) usize {
        return self.columns.items.len;
    }

    pub fn addColumn(self: *Table, allocator: Allocator) !*Column {
        const column = try allocator.create(Column);
        column.* = Column.init(allocator, self);
        for (0..self.rows()) |_| {
            try column.addCell(allocator, "");
        }
        try self.columns.append(allocator, column);
        return column;
    }

    pub fn addRow(self: *Table, allocator: Allocator) !void {
        for (self.columns.items) |column| {
            try column.addCell(allocator, "");
        }
    }

    pub fn gridSize(self: Table, units: Units) GridSize {
        var width: usize = 0;
        var height: usize = 0;
        for (self.columns.items) |column| {
            const column_dims = column.gridSize(units);
            height = @max(height, column_dims.height);
            width += column_dims.width;
        }
        return .{ .width = width, .height = height };
    }

    pub fn size(self: Table, units: Units) Size {
        const grid_size = self.gridSize(units);
        return Size{
            .width = @as(f32, @floatFromInt(grid_size.width)) * units.cell.width,
            .height = @as(f32, @floatFromInt(grid_size.height)) * units.cell.height,
        };
    }

    /// Convert table data to Markdown table format
    pub fn md(self: Table, allocator: Allocator) ![]u8 {
        if (self.columns.items.len == 0) {
            return allocator.dupe(u8, "");
        }

        var result = ArrayList(u8).initCapacity(allocator, 0) catch unreachable;
        defer result.deinit(allocator);

        // Find the maximum number of rows
        var max_rows: usize = 0;
        for (self.columns.items) |column| {
            max_rows = @max(max_rows, column.data.items.len);
        }

        if (max_rows == 0) {
            return allocator.dupe(u8, "");
        }

        // Calculate maximum width for each column
        var column_widths = allocator.alloc(usize, self.columns.items.len) catch return error.OutOfMemory;
        defer allocator.free(column_widths);

        for (self.columns.items, 0..) |column, col_idx| {
            var max_width: usize = 0;
            for (column.data.items) |cell| {
                max_width = @max(max_width, cell.value.items.len);
            }
            column_widths[col_idx] = max_width;
        }

        // Generate each row
        for (0..max_rows) |row_idx| {
            // Add pipe at start of row
            result.append(allocator, '|') catch return error.OutOfMemory;

            // Add cells for this row
            for (self.columns.items, 0..) |column, col_idx| {
                result.append(allocator, ' ') catch return error.OutOfMemory;

                const cell_value = if (row_idx < column.data.items.len)
                    column.data.items[row_idx].value.items
                else
                    "";

                result.appendSlice(allocator, cell_value) catch return error.OutOfMemory;

                // Add padding to align columns
                const padding_needed = column_widths[col_idx] - cell_value.len;
                for (0..padding_needed) |_| {
                    result.append(allocator, ' ') catch return error.OutOfMemory;
                }

                result.append(allocator, ' ') catch return error.OutOfMemory;
                result.append(allocator, '|') catch return error.OutOfMemory;
            }

            result.append(allocator, '\n') catch return error.OutOfMemory;

            // Add header separator after first row
            if (row_idx == 0) {
                result.append(allocator, '|') catch return error.OutOfMemory;
                for (column_widths) |width| {
                    result.append(allocator, ' ') catch return error.OutOfMemory;
                    for (0..width) |_| {
                        result.append(allocator, '-') catch return error.OutOfMemory;
                    }
                    result.append(allocator, ' ') catch return error.OutOfMemory;
                    result.append(allocator, '|') catch return error.OutOfMemory;
                }
                result.append(allocator, '\n') catch return error.OutOfMemory;
            }
        }

        return result.toOwnedSlice(allocator);
    }

    pub fn addSelfToScene(self: Table, scene: *Scene, allocator: Allocator, units: Units) !void {
        const cell_units = units.cell;
        const actual_position_x = @as(f32, @floatFromInt(self.position.left)) * cell_units.width;
        const actual_position_y = @as(f32, @floatFromInt(self.position.top)) * cell_units.height;
        const rect_size = self.size(units);
        const corner = 1.0 / 512.0;
        try scene.rects.append(allocator, .{
            .color = .{ 0.0, 0.0, 0.0, 0.25 },
            .x = actual_position_x,
            .y = actual_position_y,
            .width = rect_size.width,
            .height = rect_size.height,
            .corners = .{ corner, corner, corner, corner },
            .sigma = 1e-6,
        });

        var pos_x = actual_position_x;
        for (self.columns.items) |column| {
            const col_size = column.size(units);
            try column.addSelfToScene(scene, allocator, units, Vec2{ pos_x, actual_position_y });
            pos_x += col_size.width;
        }
    }

    pub fn adjacent(self: Table, grid_pos: GridPos, units: Units) Direction {
        const self_grid_size = self.gridSize(units);
        const self_right = self.position.left + self_grid_size.width;
        const self_bottom = self.position.top + self_grid_size.height;

        const is_bounded_x = grid_pos.left >= self.position.left and grid_pos.left < self_right;
        const is_bounded_y = grid_pos.top >= self.position.top and grid_pos.top < self_bottom;

        if (is_bounded_x and is_bounded_y) {
            // inside table
            return .none;
        }

        if (is_bounded_x) {
            if (grid_pos.top == self_bottom) {
                return .down;
            }
            if (grid_pos.top + 1 == self.position.top) {
                return .up;
            }
            return .none;
        }

        if (is_bounded_y) {
            if (grid_pos.left + 1 == self.position.left) {
                return .left;
            }
            if (grid_pos.left == self_right) {
                return .right;
            }
            return .none;
        }

        return .none;
    }

    /// Returns the index of the row that contains the given grid position
    /// or null if no row is found.
    /// Does not check if the grid position is within the table.
    pub fn matchingRow(self: Table, grid_pos: GridPos, units: Units) ?MatchingRow {
        if (self.rows() == 0) {
            return null;
        }
        var top = self.position.top;
        for (0..self.rows()) |i| {
            var row_height: usize = 0;
            // get the row height
            for (self.columns.items) |column| {
                const cell = column.data.items[i];
                row_height = @max(row_height, cell.gridSize(units).height);
            }
            const row_start = top;
            if (grid_pos.top >= row_start and grid_pos.top < row_start + row_height) {
                return .{
                    .index = i,
                    .top = row_start,
                    .height = row_height,
                };
            }
            top += row_height;
        }
        return null;
    }

    pub fn matchingColumn(self: Table, grid_pos: GridPos, units: Units) ?MatchingCol {
        if (self.cols() == 0) {
            return null;
        }
        var left = self.position.left;
        for (self.columns.items, 0..) |column, i| {
            const column_width = column.gridSize(units).width;
            const column_start = left;
            if (grid_pos.left >= column_start and grid_pos.left < column_start + column_width) {
                return .{
                    .index = i,
                    .left = column_start,
                    .width = column_width,
                };
            }
            left += column_width;
        }
        return null;
    }
};
