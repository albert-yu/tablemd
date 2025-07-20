const std = @import("std");
const ArrayList = std.ArrayListUnmanaged;
const Allocator = std.mem.Allocator;
const grid = @import("render/dot_grid.zig");
const rect = @import("render/rect.zig");
const text = @import("render/text.zig");
const Vec2 = @import("zm").Vec2f;

const RectElement = rect.RectElement;
const TextElement = text.TextElement;
const Size2D = grid.Size2D;

const GRID_N = grid.GRID_N;
const Color = [4]f32;

const Units = struct {
    cell: Size2D,
    text: Size2D,
};

pub const Scene = struct {
    rects: ArrayList(RectElement),
    texts: ArrayList(TextElement),

    pub fn init(allocator: Allocator) Scene {
        return Scene{
            .rects = ArrayList(RectElement).initCapacity(allocator, 0) catch unreachable,
            .texts = ArrayList(TextElement).initCapacity(allocator, 0) catch unreachable,
        };
    }

    pub fn deinit(self: *Scene, allocator: Allocator) void {
        self.rects.deinit(allocator);
        self.texts.deinit(allocator);
    }

    pub fn clear(self: *Scene) void {
        self.rects.clearRetainingCapacity();
        self.texts.clearRetainingCapacity();
    }
};

/// Represents any arbitrary position in 2D space
/// rather than a specific grid cell
pub const PosVec2 = struct {
    x: f32,
    y: f32,
};

pub const GridPos = struct {
    left: usize = 0,
    top: usize = 0,
};

pub const GridPosText = struct {
    left: usize = 0,
    top: usize = 0,
    char_offset: ?usize = null,
};

pub const Cell = struct {
    value: []const u8,

    pub fn size(self: Cell, units: Units) Size2D {
        const cell_units = units.cell;
        const text_units = units.text;

        var height: f32 = units.cell.height;
        var width: f32 = 0.0;
        var curr_line_width: f32 = 0.0;
        for (self.value) |char| {
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

    pub fn addSelfToScene(self: Cell, scene: *Scene, allocator: Allocator, units: Units, position: PosVec2) !void {
        // This is addition is here because otherwise, the
        // text starts above the first row. Reason being that
        // the text bearing_y is negative and pulls the text
        // upwards
        var pos_y = position.y + units.cell.height;
        var i: usize = 0;
        var start: usize = i;
        while (i < self.value.len) : (i += 1) {
            const char = self.value[i];
            if (char == '\n') {
                // send the current line to the scene
                try scene.texts.append(allocator, .{
                    .text = self.value[start..i],
                    .x = position.x,
                    .y = pos_y,
                });
                i += 1; // skip the newline
                start = i;
                pos_y += units.text.height;
                continue;
            }
        }
        if (start < self.value.len) {
            try scene.texts.append(allocator, .{
                .text = self.value[start..self.value.len],
                .x = position.x,
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

    pub fn init(allocator: Allocator) Column {
        return Column{
            .data = ArrayList(Cell).initCapacity(allocator, 0) catch unreachable,
        };
    }

    pub fn deinit(self: *Column, allocator: Allocator) void {
        // for (self.data.items) |cell| {
        //     // TODO: deinit cell
        //     // cell.deinit(allocator);
        // }
        self.data.deinit(allocator);
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

    pub fn addSelfToScene(self: Column, scene: *Scene, allocator: Allocator, units: Units, position: PosVec2) !void {
        var pos_y = position.y;
        for (self.data.items) |cell| {
            const cell_dims = cell.size(units);
            try cell.addSelfToScene(scene, allocator, units, .{
                .x = position.x,
                .y = pos_y,
            });
            pos_y += cell_dims.height;
        }
    }
};

pub const Table = struct {
    position: GridPos,
    columns: ArrayList(Column),

    pub fn init(allocator: Allocator) Table {
        return Table{
            .position = .{ .left = 0, .top = 0 },
            .columns = ArrayList(Column).initCapacity(allocator, 0) catch unreachable,
        };
    }

    pub fn deinit(self: *Table, allocator: Allocator) void {
        for (self.columns.items) |*column| {
            column.deinit(allocator);
        }
        self.columns.deinit(allocator);
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
                max_width = @max(max_width, cell.value.len);
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
                    column.data.items[row_idx].value
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
            try column.addSelfToScene(scene, allocator, units, .{
                .x = pos_x,
                .y = actual_position_y,
            });
            pos_x += col_size.width;
        }
    }
};

pub const CursorType = enum {
    cell,
    text,
};

pub const Cursor = union(CursorType) {
    cell: GridPos,
    text: GridPosText,

    pub fn getRect(self: Cursor, units: Units, color: Color) RectElement {
        const corner = 1.0 / 512.0;
        const corners = .{ corner, corner, corner, corner };
        return switch (self) {
            .cell => |cell_pos| .{
                .color = color,
                .x = @as(f32, @floatFromInt(cell_pos.left)) * units.cell.width,
                .y = @as(f32, @floatFromInt(cell_pos.top)) * units.cell.height,
                .width = units.cell.width,
                .height = units.cell.height,
                .corners = corners,
                .sigma = 1e-6,
            },
            .text => |text_pos| .{
                .color = color,
                // TODO: fix this to use offset
                .x = @as(f32, @floatFromInt(text_pos.left)) * units.text.width,
                .y = @as(f32, @floatFromInt(text_pos.top)) * units.text.height,
                .width = units.text.width,
                .height = units.text.height,
                .corners = corners,
                .sigma = 1e-6,
            },
        };
    }
};

pub const UI = struct {
    tables: ArrayList(Table),
    active_cursor: ?Cursor,
    hover_cursor: ?Cursor,
    units: Units,

    pub fn init(allocator: Allocator, units: Units) UI {
        return .{
            .tables = ArrayList(Table).initCapacity(allocator, 0) catch unreachable,
            .active_cursor = null,
            .hover_cursor = null,
            .units = units,
        };
    }

    pub fn deinit(self: *UI, allocator: Allocator) void {
        for (self.tables.items) |*table| {
            table.deinit(allocator);
        }
        self.tables.deinit(allocator);
    }

    pub fn handleMouseDown(self: *UI, p: Vec2) void {
        self.active_cursor = self.getCursor(p);
    }

    pub fn handleMouseMove(self: *UI, p: Vec2) void {
        self.hover_cursor = self.getCursor(p);
    }

    pub fn getCursor(self: UI, p: Vec2) Cursor {
        const cell_pos = self.getCellPosition(p);
        // TODO: handle text cursor
        return Cursor{ .cell = cell_pos };
    }

    pub fn addSelfToScene(self: UI, allocator: Allocator, scene: *Scene) !void {
        for (self.tables.items) |table| {
            try table.addSelfToScene(scene, allocator, self.units);
        }
        if (self.active_cursor) |cursor| {
            try scene.rects.append(allocator, cursor.getRect(self.units, .{ 0.0, 1.0, 0.0, 0.75 }));
        }
        if (self.hover_cursor) |cursor| {
            try scene.rects.append(allocator, cursor.getRect(self.units, .{ 1.0, 0.0, 0.0, 1.25 }));
        }
    }

    fn getCellPosition(self: UI, p: Vec2) GridPos {
        const row = self.getIndexOfMaxGridPointBoundedBy(p[1]);
        const col = self.getIndexOfMaxGridPointBoundedBy(p[0]);
        return .{ .left = col, .top = row };
    }

    /// Uses x position, but we can reuse this for y
    /// since the grid cells are square
    fn getIndexOfMaxGridPointBoundedBy(self: UI, upper_bound: f32) usize {
        var max_i: usize = 0;
        while (max_i < GRID_N) : (max_i += 1) {
            const x = self.units.cell.width * @as(f32, @floatFromInt(max_i));
            if (x + self.units.cell.width > upper_bound) {
                break;
            }
        }
        return max_i;
    }
};
