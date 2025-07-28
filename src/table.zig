const std = @import("std");
const ArrayList = std.ArrayListUnmanaged;
const Allocator = std.mem.Allocator;
const grid = @import("render/dot_grid.zig");
const scene_mod = @import("render/scene.zig");
const Vec2 = @import("zm").Vec2f;
const sokol = @import("sokol");
const sg = sokol.gfx;
const theme = @import("theme.zig");

const Scene = scene_mod.Scene;
const Size = grid.Size;

const TABLE_BG_COLOR: sg.Color = theme.DARK_THEME.table_background_color;

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
                    .color = theme.DARK_THEME.text_color,
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
                .color = theme.DARK_THEME.text_color,
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
        const self_size = self.size(units);
        for (self.data.items, 0..) |cell, i| {
            const cell_dims = cell.size(units);
            try cell.addSelfToScene(scene, allocator, units, Vec2{ position[0], pos_y });
            pos_y += cell_dims.height;
            if (i < self.data.items.len - 1) {
                try scene.rects.append(allocator, .{
                    .color = .{ .r = 1.0, .g = 1.0, .b = 1.0, .a = 1.0 },
                    .x = position[0],
                    .y = pos_y - cell_dims.height / 50.0,
                    .width = self_size.width,
                    .height = cell_dims.height / 50.0,
                    .corners = .{ 0, 0, 0, 0 },
                    .sigma = 1e-6,
                });
            }
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

    pub fn insertColumn(self: *Table, allocator: Allocator, index: usize) !*Column {
        if (index > self.columns.items.len) {
            return error.IndexOutOfBounds;
        }

        const column = try allocator.create(Column);
        column.* = Column.init(allocator, self);
        for (0..self.rows()) |_| {
            try column.addCell(allocator, "");
        }
        try self.columns.insert(allocator, index, column);
        return column;
    }

    pub fn addRow(self: *Table, allocator: Allocator) !void {
        for (self.columns.items) |column| {
            try column.addCell(allocator, "");
        }
    }

    pub fn insertRow(self: *Table, allocator: Allocator, index: usize) !void {
        if (index > self.rows()) {
            return error.IndexOutOfBounds;
        }

        for (self.columns.items) |column| {
            const cell = try Cell.init(allocator, "", column);
            try column.data.insert(allocator, index, cell);
        }
    }

    pub fn removeColumn(self: *Table, allocator: Allocator, index: usize) void {
        var column = self.columns.orderedRemove(index);
        column.deinit(allocator);
        allocator.destroy(column);
    }

    pub fn removeRow(self: *Table, allocator: Allocator, index: usize) void {
        for (self.columns.items) |column| {
            var cell = column.data.orderedRemove(index);
            cell.deinit(allocator);
        }
    }

    pub fn rowIsEmpty(self: Table, row_index: usize) bool {
        if (row_index >= self.rows()) {
            return false;
        }
        for (self.columns.items) |column| {
            const cell = column.data.items[row_index];
            if (cell.value.items.len > 0) {
                return false;
            }
        }
        return true;
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
            std.log.warn("No columns in table", .{});
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
            std.log.warn("No rows in table", .{});
            return allocator.dupe(u8, "");
        }

        // Calculate maximum width for each column
        var column_widths = try allocator.alloc(usize, self.columns.items.len);
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
            try result.append(allocator, '|');

            // Add cells for this row
            for (self.columns.items, 0..) |column, col_idx| {
                try result.append(allocator, ' ');

                const cell_value = if (row_idx < column.data.items.len)
                    column.data.items[row_idx].value.items
                else
                    "";

                try result.appendSlice(allocator, cell_value);

                // Add padding to align columns
                const padding_needed = column_widths[col_idx] - cell_value.len;
                for (0..padding_needed) |_| {
                    try result.append(allocator, ' ');
                }

                try result.append(allocator, ' ');
                try result.append(allocator, '|');
            }

            try result.append(allocator, '\n');

            // Add header separator after first row
            if (row_idx == 0) {
                try result.append(allocator, '|');
                for (column_widths) |width| {
                    try result.append(allocator, ' ');
                    for (0..width) |_| {
                        try result.append(allocator, '-');
                    }
                    try result.append(allocator, ' ');
                    try result.append(allocator, '|');
                }
                try result.append(allocator, '\n');
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
            .color = TABLE_BG_COLOR,
            .x = actual_position_x,
            .y = actual_position_y,
            .width = rect_size.width,
            .height = rect_size.height,
            .corners = .{ corner, corner, corner, corner },
            .sigma = 1e-6,
        });

        var pos_x = actual_position_x;
        for (self.columns.items, 0..) |column, i| {
            const col_size = column.size(units);
            try column.addSelfToScene(scene, allocator, units, Vec2{ pos_x, actual_position_y });

            // Add white column separator line (except before the first column)
            if (i > 0) {
                try scene.rects.append(allocator, .{
                    .color = .{ .r = 1.0, .g = 1.0, .b = 1.0, .a = 1.0 },
                    .x = pos_x - cell_units.width / 50.0,
                    .y = actual_position_y,
                    .width = cell_units.width / 50.0,
                    .height = rect_size.height,
                    .corners = .{ 0, 0, 0, 0 },
                    .sigma = 1e-6,
                });
            }
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

    pub fn serialize(self: Table, allocator: Allocator) ![]u8 {
        var buffer = std.ArrayList(u8).init(allocator);
        defer buffer.deinit();
        var writer = buffer.writer();

        // Write table position
        try writer.writeInt(usize, self.position.left, .little);
        try writer.writeInt(usize, self.position.top, .little);

        // Write number of columns
        try writer.writeInt(usize, self.columns.items.len, .little);

        // Write each column
        for (self.columns.items) |column| {
            // Write number of cells in column
            try writer.writeInt(usize, column.data.items.len, .little);

            // Write each cell
            for (column.data.items) |cell| {
                // Write cell value length and data
                try writer.writeInt(usize, cell.value.items.len, .little);
                try writer.writeAll(cell.value.items);
            }
        }

        return buffer.toOwnedSlice();
    }

    pub fn deserialize(allocator: Allocator, data: []const u8) !Table {
        var stream = std.io.fixedBufferStream(data);
        var reader = stream.reader();

        // Read table position
        const left = try reader.readInt(usize, .little);
        const top = try reader.readInt(usize, .little);

        var table = Table.init(allocator);
        table.position = .{ .left = left, .top = top };

        // Read number of columns
        const num_columns = try reader.readInt(usize, .little);

        // Read each column
        for (0..num_columns) |_| {
            const column = try allocator.create(Column);
            column.* = Column.init(allocator, &table);

            // Read number of cells
            const num_cells = try reader.readInt(usize, .little);

            // Read each cell
            for (0..num_cells) |_| {
                // Read cell value length
                const value_len = try reader.readInt(usize, .little);

                // Read cell value data
                const value_data = try allocator.alloc(u8, value_len);
                _ = try reader.readAll(value_data);

                const cell = try Cell.init(allocator, value_data, column);
                try column.data.append(allocator, cell);

                allocator.free(value_data);
            }

            try table.columns.append(allocator, column);
        }

        return table;
    }
};

test "table serialization and deserialization" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create a test table
    var original_table = Table.init(allocator);
    defer original_table.deinit(allocator);

    original_table.position = .{ .left = 5, .top = 10 };

    // Add some columns and cells
    const col1 = try original_table.addColumn(allocator);
    const col2 = try original_table.addColumn(allocator);

    try original_table.addRow(allocator);
    try original_table.addRow(allocator);

    // Set some cell values
    col1.data.items[0].value.clearAndFree(allocator);
    try col1.data.items[0].value.appendSlice(allocator, "Hello");

    col1.data.items[1].value.clearAndFree(allocator);
    try col1.data.items[1].value.appendSlice(allocator, "World");

    col2.data.items[0].value.clearAndFree(allocator);
    try col2.data.items[0].value.appendSlice(allocator, "Test");

    col2.data.items[1].value.clearAndFree(allocator);
    try col2.data.items[1].value.appendSlice(allocator, "Data");

    // Serialize the table
    const serialized = try original_table.serialize(allocator);
    defer allocator.free(serialized);

    // Deserialize the table
    var deserialized_table = try Table.deserialize(allocator, serialized);
    defer deserialized_table.deinit(allocator);

    // Verify the deserialized table matches the original
    try testing.expectEqual(original_table.position.left, deserialized_table.position.left);
    try testing.expectEqual(original_table.position.top, deserialized_table.position.top);
    try testing.expectEqual(original_table.cols(), deserialized_table.cols());
    try testing.expectEqual(original_table.rows(), deserialized_table.rows());

    // Check cell values
    try testing.expectEqualStrings("Hello", deserialized_table.columns.items[0].data.items[0].value.items);
    try testing.expectEqualStrings("World", deserialized_table.columns.items[0].data.items[1].value.items);
    try testing.expectEqualStrings("Test", deserialized_table.columns.items[1].data.items[0].value.items);
    try testing.expectEqualStrings("Data", deserialized_table.columns.items[1].data.items[1].value.items);
}

test "empty table serialization" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // Create an empty table
    var original_table = Table.init(allocator);
    defer original_table.deinit(allocator);

    // Serialize and deserialize
    const serialized = try original_table.serialize(allocator);
    defer allocator.free(serialized);

    var deserialized_table = try Table.deserialize(allocator, serialized);
    defer deserialized_table.deinit(allocator);

    // Verify empty table properties
    try testing.expectEqual(@as(usize, 0), deserialized_table.cols());
    try testing.expectEqual(@as(usize, 0), deserialized_table.rows());
}
