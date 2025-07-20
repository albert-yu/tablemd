const std = @import("std");
const sokol = @import("sokol");
const ArrayList = std.ArrayListUnmanaged;
const Allocator = std.mem.Allocator;
const grid = @import("render/dot_grid.zig");
const rect = @import("render/rect.zig");
const text = @import("render/text.zig");
const Vec2 = @import("zm").Vec2f;
const sapp = sokol.app;
const Keycode = sapp.Keycode;

const RectElement = rect.RectElement;
const TextElement = text.TextElement;
const Size2D = grid.Size2D;

const GRID_N = grid.GRID_N;
const Color = [4]f32;

const Units = struct {
    cell: Size2D,
    text: Size2D,
};

const ClientRect = struct {
    pos: Vec2,
    size: Size2D,
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

pub const GridPos = struct {
    left: usize = 0,
    top: usize = 0,
};

pub const Cell = struct {
    value: ArrayList(u8),

    pub fn init(allocator: Allocator, content: []const u8) !Cell {
        var value = try ArrayList(u8).initCapacity(allocator, content.len);
        value.appendSlice(allocator, content) catch unreachable;
        return Cell{ .value = value };
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

    pub fn init(allocator: Allocator) Column {
        return Column{
            .data = ArrayList(Cell).initCapacity(allocator, 0) catch unreachable,
        };
    }

    pub fn deinit(self: *Column, allocator: Allocator) void {
        for (self.data.items) |*cell| {
            cell.deinit(allocator);
        }
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
};

const CellPos = struct {
    cell: *Cell,
    column: *Column,
    pos: Vec2,
};

const TextPos = struct {
    cell: *Cell,
    column: *Column,
    pos: Vec2,
    char_offset: usize,
};

const CursorType = enum {
    empty,
    cell,
    text,
};

pub const Cursor = union(CursorType) {
    empty: GridPos,
    cell: CellPos,
    text: TextPos,

    pub fn getRect(self: Cursor, units: Units, color: Color) RectElement {
        const corner = 1.0 / 512.0;
        const corners = .{ corner, corner, corner, corner };
        return switch (self) {
            .empty => |grid_pos| .{
                .color = color,
                .x = @as(f32, @floatFromInt(grid_pos.left)) * units.cell.width,
                .y = @as(f32, @floatFromInt(grid_pos.top)) * units.cell.height,
                .width = units.cell.width,
                .height = units.cell.height,
                .corners = corners,
                .sigma = 1e-6,
            },
            .cell => |cell_info| .{
                .color = color,
                .x = cell_info.pos[0],
                .y = cell_info.pos[1],
                .width = cell_info.column.size(units).width,
                .height = cell_info.cell.size(units).height,
                .corners = corners,
                .sigma = 1e-6,
            },
            .text => |text_pos| .{
                .color = color,
                .x = text_pos.pos[0],
                .y = text_pos.pos[1],
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

    pub fn handleChar(self: *UI, allocator: Allocator, char_code: u32) !void {
        if (self.active_cursor) |cursor| {
            switch (cursor) {
                .empty => {
                    // TODO: handle input on empty
                    // it should create a new table
                    // if the cell isn't adjacent to
                    // an existing table
                },
                .cell => {
                    // Do nothing
                },
                .text => |text_pos| {
                    // Convert u32 to u8, handling potential overflow
                    const char: u8 = @truncate(char_code);
                    try text_pos.cell.value.insert(allocator, text_pos.char_offset, char);
                },
            }
        }
    }

    pub fn handleKeyDown(self: *UI, key_code: Keycode) void {
        switch (key_code) {
            .BACKSPACE => self.handleBackspace(),
            // TODO: handle tab, enter
            // tab should move to next cell to the right
            // enter should create a new row or move to next cell down
            else => {},
        }
    }

    fn handleBackspace(self: *UI) void {
        if (self.active_cursor) |cursor| {
            switch (cursor) {
                .empty => {
                    // TODO: handle input on empty
                },
                .cell => {},
                .text => |text_pos| {
                    _ = text_pos.cell.value.orderedRemove(text_pos.char_offset);
                },
            }
        }
    }

    pub fn addSelfToScene(self: UI, allocator: Allocator, scene: *Scene) !void {
        for (self.tables.items) |table| {
            try table.addSelfToScene(scene, allocator, self.units);
        }
        if (self.active_cursor) |cursor| {
            try scene.rects.append(allocator, cursor.getRect(self.units, .{ 0.5, 0.8, 1.0, 0.8 }));
        }
        if (self.hover_cursor) |cursor| {
            try scene.rects.append(allocator, cursor.getRect(self.units, .{ 0.7, 0.9, 1.0, 0.4 }));
        }
    }

    fn getCursor(self: *UI, p: Vec2) Cursor {
        // Check if there's a Cell at this position and use its size
        if (self.getCellAt(p)) |cell_info| {
            if (self.getTextPositionAt(p, cell_info)) |text_pos| {
                return .{
                    .text = text_pos,
                };
            }
            return .{
                .cell = cell_info,
            };
        }

        // Default to grid cell size if no Cell found
        const cell_pos = self.getCellPosition(p);
        return .{
            .empty = cell_pos,
        };
    }

    fn getTextPositionAt(self: *UI, p: Vec2, containing_cell: CellPos) ?TextPos {
        const cell = containing_cell.cell;
        const lines = countLines(cell);
        var offset: usize = 0;
        var x: f32 = containing_cell.pos[0];
        for (0..lines) |target_line| {
            var line_x = x;
            const line_y = containing_cell.pos[1] + self.units.cell.height * @as(f32, @floatFromInt(target_line));
            while (offset < cell.value.items.len) : (offset += 1) {
                const char = cell.value.items[offset];
                if (char == '\n') {
                    // reset x to start
                    x = containing_cell.pos[0];
                    break;
                }
                line_x += self.units.text.width;
                const char_pos = Vec2{ line_x, line_y };
                if (clientRectContains(.{ .pos = char_pos, .size = self.units.text }, p)) {
                    return TextPos{
                        .cell = cell,
                        .column = containing_cell.column,
                        .pos = Vec2{ line_x, line_y },
                        .char_offset = offset,
                    };
                }
            }
        }
        return null;
    }

    fn getCellAt(self: *UI, p: Vec2) ?CellPos {
        for (self.tables.items) |table| {
            const table_start_x = @as(f32, @floatFromInt(table.position.left)) * self.units.cell.width;
            const table_start_y = @as(f32, @floatFromInt(table.position.top)) * self.units.cell.height;

            // Check if position is within table area
            if (p[0] >= table_start_x and p[1] >= table_start_y) {
                var current_x = table_start_x;
                const current_y = table_start_y;

                // Iterate through columns to find which one contains the point
                for (table.columns.items) |*column| {
                    const column_size = column.size(self.units);

                    // Check if point is within this column's width
                    if (p[0] >= current_x and p[0] < current_x + column_size.width) {
                        var cell_y = current_y;

                        // Iterate through cells in this column
                        for (column.data.items) |*cell| {
                            const cell_height = cell.size(self.units).height;

                            // Check if point is within this cell's height
                            if (p[1] >= cell_y and p[1] < cell_y + cell_height) {
                                return CellPos{
                                    .cell = cell,
                                    .column = column,
                                    .pos = Vec2{ current_x, cell_y },
                                };
                            }

                            cell_y += cell_height;
                        }

                        // Point is within column width but below all cells
                        break;
                    }

                    current_x += column_size.width;
                }
            }
        }
        return null;
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

fn clientRectContains(r: ClientRect, p: Vec2) bool {
    return p[0] >= r.pos[0] and p[0] < r.pos[0] + r.size.width and p[1] >= r.pos[1] and p[1] < r.pos[1] + r.size.height;
}

fn countLines(cell: *const Cell) usize {
    var lines: usize = 1;
    for (cell.value.items) |char| {
        if (char == '\n') lines += 1;
    }
    return lines;
}
