const std = @import("std");
const ArrayList = std.ArrayListUnmanaged;
const Allocator = std.mem.Allocator;
const grid = @import("render/dot_grid.zig");
const scene_mod = @import("render/scene.zig");
const Vec2 = @import("zm").Vec2f;

const Scene = scene_mod.Scene;
const Size2D = grid.Size2D;

pub const Units = struct {
    cell: Size2D,
    text: Size2D,
};

pub const GridPos = struct {
    left: usize = 0,
    top: usize = 0,
};

pub const Direction = enum {
    none,
    left,
    right,
    up,
    down,
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

    pub fn size(self: Cell, units: Units) Size2D {
        const cell_units = units.cell;
        const text_units = units.text;

        var height: f32 = units.cell.height;
        var width: f32 = 0.0;
        var curr_line_width: f32 = 0.0;
        for (self.value.items) |char| {
            if (char == '\n') {
                width = @max(width, curr_line_width);
                curr_line_width = 0.0;
                height += text_units.height;
                continue;
            }
            curr_line_width += text_units.width;
        }
        width = @max(width, curr_line_width);
        const container_width = cell_units.width * divCeil(width, cell_units.width);
        return .{ .width = container_width, .height = height };
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

fn divCeil(top: f32, bottom: f32) f32 {
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

    pub fn size(self: Column, units: Units) Size2D {
        var width: f32 = 0.0;
        var height: f32 = 0.0;
        for (self.data.items) |cell| {
            const cell_dims = cell.size(units);
            width = @max(width, cell_dims.width);
            height += cell_dims.height;
        }
        return .{ .width = width, .height = height };
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
        try self.columns.append(allocator, column);
        return column;
    }

    pub fn size(self: Table, units: Units) Size2D {
        var width: f32 = 0.0;
        var height: f32 = 0.0;
        for (self.columns.items) |column| {
            const column_dims = column.size(units);
            height = @max(height, column_dims.height);
            width += column_dims.width;
        }
        return .{ .width = width, .height = height };
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
        const cell_units = units.cell;
        const actual_position_x = @as(f32, @floatFromInt(grid_pos.left)) * cell_units.width;
        const actual_position_y = @as(f32, @floatFromInt(grid_pos.top)) * cell_units.height;

        const self_left = @as(f32, @floatFromInt(self.position.left)) * cell_units.width;
        const self_top = @as(f32, @floatFromInt(self.position.top)) * cell_units.height;
        const self_size = self.size(units);
        const self_bottom = self_top + self_size.height;
        const self_right = self_left + self_size.width;
        const is_bounded_x = actual_position_x >= self_left and actual_position_x < self_right;
        const is_bounded_y = actual_position_y >= self_top and actual_position_y < self_bottom;
        if (is_bounded_x and is_bounded_y) {
            // inside table
            return .none;
        }
        if (is_bounded_x) {
            if (actual_position_y >= self_bottom and actual_position_y < self_bottom + cell_units.height) {
                return .down;
            }
            if (actual_position_y < self_top and actual_position_y >= self_top - cell_units.height) {
                return .up;
            }
            return .none;
        }
        if (is_bounded_y) {
            if (actual_position_x >= self_left - cell_units.width and actual_position_x < self_left) {
                return .left;
            }
            if (actual_position_x >= self_right and actual_position_x < self_right + cell_units.width) {
                return .right;
            }
            return .none;
        }

        return .none;
    }
};
