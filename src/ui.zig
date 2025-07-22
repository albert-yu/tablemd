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
const table_mod = @import("table.zig");
const scene_mod = @import("render/scene.zig");

const RectElement = rect.RectElement;
const TextElement = text.TextElement;
const Size2D = grid.Size;

const GRID_N = grid.GRID_N;
const Color = [4]f32;

// Re-export table types for backward compatibility
pub const Table = table_mod.Table;
const Cell = table_mod.Cell;
pub const Scene = scene_mod.Scene;
const GridPos = table_mod.GridPos;
const Units = table_mod.Units;
const Direction = table_mod.Direction;
const GridSize = table_mod.GridSize;

const ClientRect = struct {
    pos: Vec2,
    size: Size2D,
};

const EmptyPos = struct {
    grid_pos: GridPos,
    grid_size: GridSize,
};

const CellIndex = struct {
    table_index: usize,
    column_index: usize,
    row_index: usize,
};

const CellPos = struct {
    cell_index: CellIndex,
    pos: Vec2,
};

const TextPos = struct {
    cell_index: CellIndex,
    pos: Vec2,
    char_offset: usize,
};

const CursorType = enum {
    empty,
    cell,
    text,
};

pub const Cursor = union(CursorType) {
    empty: EmptyPos,
    cell: CellPos,
    text: TextPos,

    pub fn getRect(self: Cursor, ui: *UI, color: Color) RectElement {
        const corner = 1.0 / 512.0;
        const corners = .{ corner, corner, corner, corner };
        const units = ui.units;
        return switch (self) {
            .empty => |empty_pos| .{
                .color = color,
                .x = units.cell.width * @as(f32, @floatFromInt(empty_pos.grid_pos.left)),
                .y = units.cell.height * @as(f32, @floatFromInt(empty_pos.grid_pos.top)),
                .width = units.cell.width * @as(f32, @floatFromInt(empty_pos.grid_size.width)),
                .height = units.cell.height * @as(f32, @floatFromInt(empty_pos.grid_size.height)),
                .corners = corners,
                .sigma = 1e-6,
            },
            .cell => |cell_info| blk: {
                if (ui.getCellFromIndex(cell_info.cell_index)) |cell| {
                    break :blk .{
                        .color = color,
                        .x = cell_info.pos[0],
                        .y = cell_info.pos[1],
                        .width = cell.column.size(units).width,
                        .height = cell.size(units).height,
                        .corners = corners,
                        .sigma = 1e-6,
                    };
                } else {
                    break :blk .{
                        .color = color,
                        .x = cell_info.pos[0],
                        .y = cell_info.pos[1],
                        .width = units.cell.width,
                        .height = units.cell.height,
                        .corners = corners,
                        .sigma = 1e-6,
                    };
                }
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
    tables: ArrayList(*Table),
    active_cursor: ?Cursor,
    hover_cursor: ?Cursor,
    units: Units,

    pub fn init(allocator: Allocator, units: Units) UI {
        return .{
            .tables = ArrayList(*Table).initCapacity(allocator, 0) catch unreachable,
            .active_cursor = null,
            .hover_cursor = null,
            .units = units,
        };
    }

    pub fn deinit(self: *UI, allocator: Allocator) void {
        for (self.tables.items) |table| {
            table.deinit(allocator);
            allocator.destroy(table);
        }
        self.tables.deinit(allocator);
    }

    pub fn getCellFromIndex(self: *UI, cell_index: CellIndex) ?*Cell {
        if (cell_index.table_index >= self.tables.items.len) return null;
        const table = self.tables.items[cell_index.table_index];

        if (cell_index.column_index >= table.columns.items.len) return null;
        const column = table.columns.items[cell_index.column_index];

        if (cell_index.row_index >= column.data.items.len) return null;
        return &column.data.items[cell_index.row_index];
    }

    fn getCellIndex(self: *UI, cell: *Cell) ?CellIndex {
        for (self.tables.items, 0..) |table, table_idx| {
            for (table.columns.items, 0..) |column, col_idx| {
                for (column.data.items, 0..) |*table_cell, row_idx| {
                    if (table_cell == cell) {
                        return CellIndex{
                            .table_index = table_idx,
                            .column_index = col_idx,
                            .row_index = row_idx,
                        };
                    }
                }
            }
        }
        return null;
    }

    pub fn addTable(self: *UI, allocator: Allocator) !*Table {
        const table = try allocator.create(Table);
        table.* = Table.init(allocator);
        try self.tables.append(allocator, table);
        return table;
    }

    pub fn handleMouseDown(self: *UI, p: Vec2) void {
        self.active_cursor = self.getCursor(p);
    }

    pub fn handleMouseMove(self: *UI, p: Vec2) void {
        self.hover_cursor = self.getCursor(p);
    }

    pub fn handleChar(self: *UI, allocator: Allocator, char_code: u32) !void {
        if (!isPrintableChar(char_code)) {
            return;
        }
        if (self.active_cursor) |cursor| {
            switch (cursor) {
                .empty => {
                    var adjacent_table: ?*Table = null;
                    var direction: Direction = .none;

                    for (self.tables.items) |table| {
                        const adj = table.adjacent(cursor.empty.grid_pos, self.units);
                        if (adj == .down or adj == .right) {
                            // For now, only grow down and to the right
                            // TODO: handle up and left
                            if (adjacent_table) |_| {
                                // Only possible once left and up are implemented
                                std.log.info("multiple adjacent tables, ignoring", .{});
                                return;
                            }
                            adjacent_table = table;
                            direction = adj;
                            break;
                        }
                    }
                    if (adjacent_table) |table| {
                        switch (direction) {
                            .right => {
                                const matching_row = table.matchingRow(cursor.empty.grid_pos, self.units) orelse {
                                    std.log.info("no matching row", .{});
                                    return;
                                };

                                // Find table index
                                const table_idx = for (self.tables.items, 0..) |t, idx| {
                                    if (t == table) break idx;
                                } else unreachable;

                                var col = try table.addColumn(allocator);
                                const char: u8 = @truncate(char_code);
                                const new_y = @as(f32, @floatFromInt(matching_row.top)) * self.units.cell.height;
                                const new_x = @as(f32, @floatFromInt(cursor.empty.grid_pos.left)) * self.units.cell.width + self.units.text.width;
                                const row_i = matching_row.index;
                                const cell = &col.data.items[row_i];
                                try cell.value.insert(allocator, 0, char);
                                self.active_cursor = .{
                                    .text = .{
                                        .cell_index = CellIndex{
                                            .table_index = table_idx,
                                            .column_index = table.columns.items.len - 1, // Last column added
                                            .row_index = row_i,
                                        },
                                        .pos = Vec2{ new_x, new_y },
                                        .char_offset = 0,
                                    },
                                };
                            },
                            .down => {
                                const matching_col = table.matchingColumn(cursor.empty.grid_pos, self.units) orelse {
                                    std.log.info("no matching col", .{});
                                    return;
                                };

                                // Find table index
                                const table_idx = for (self.tables.items, 0..) |t, idx| {
                                    if (t == table) break idx;
                                } else unreachable;

                                try table.addRow(allocator);
                                const row_i = table.rows() - 1;
                                const col_i = matching_col.index;
                                const char: u8 = @truncate(char_code);
                                const cursor_x = @as(f32, @floatFromInt(matching_col.left)) * self.units.cell.width;
                                const new_x = cursor_x + self.units.text.width;
                                const y = @as(f32, @floatFromInt(cursor.empty.grid_pos.top)) * self.units.cell.height;
                                const cell = &table.columns.items[col_i].data.items[row_i];
                                try cell.value.insert(allocator, 0, char);
                                self.active_cursor = .{
                                    .text = .{
                                        .cell_index = CellIndex{
                                            .table_index = table_idx,
                                            .column_index = col_i,
                                            .row_index = row_i,
                                        },
                                        .pos = Vec2{ new_x, y },
                                        .char_offset = 0,
                                    },
                                };
                            },
                            else => {},
                        }
                    } else {
                        // Create a new table at this position
                        const table = try self.addTable(allocator);
                        table.position = cursor.empty.grid_pos;
                        const col = try table.addColumn(allocator);
                        try col.addCell(allocator, "");
                        const char: u8 = @truncate(char_code);
                        const cell = &col.data.items[0]; // First cell in the new column
                        try cell.value.insert(allocator, 0, char);

                        // Set cursor to text position after the inserted character
                        const cell_x = @as(f32, @floatFromInt(table.position.left)) * self.units.cell.width;
                        const cell_y = @as(f32, @floatFromInt(table.position.top)) * self.units.cell.height;
                        const table_idx = self.tables.items.len - 1; // Last table added
                        self.active_cursor = .{
                            .text = .{
                                .cell_index = CellIndex{
                                    .table_index = table_idx,
                                    .column_index = 0,
                                    .row_index = 0,
                                },
                                .pos = Vec2{ cell_x + self.units.text.width, cell_y },
                                .char_offset = 0,
                            },
                        };
                    }
                },
                .cell => |cell_pos| {
                    const cell = self.getCellFromIndex(cell_pos.cell_index) orelse return;
                    // clear the current text
                    cell.value.clearRetainingCapacity();
                    const char: u8 = @truncate(char_code);
                    try cell.value.insert(allocator, 0, char);
                    self.active_cursor = .{
                        .text = .{
                            .cell_index = cell_pos.cell_index,
                            .pos = Vec2{ cell_pos.pos[0] + self.units.text.width, cell_pos.pos[1] },
                            .char_offset = 0,
                        },
                    };
                },
                .text => |text_pos| {
                    const cell = self.getCellFromIndex(text_pos.cell_index) orelse return;
                    const curr_table_width = cell.column.table.gridSize(self.units).width;
                    // Convert u32 to u8, handling potential overflow
                    const char: u8 = @truncate(char_code);
                    const new_offset = if (cell.value.items.len == 0) 0 else text_pos.char_offset + 1;
                    try cell.value.insert(allocator, new_offset, char);
                    const new_table_width = cell.column.table.gridSize(self.units).width;
                    const new_x = text_pos.pos[0] + self.units.text.width;
                    self.active_cursor = .{
                        .text = .{
                            .cell_index = text_pos.cell_index,
                            .pos = .{ new_x, text_pos.pos[1] },
                            .char_offset = new_offset,
                        },
                    };
                    if (new_table_width > curr_table_width) {
                        self.shiftTablesRight(cell.column.table, new_table_width - curr_table_width);
                    }
                },
            }
        }
    }

    pub fn handleKeyDown(self: *UI, allocator: Allocator, key_code: Keycode) void {
        switch (key_code) {
            .BACKSPACE => self.handleBackspace(),
            .ENTER => self.handleEnter(allocator),
            // TODO: handle tab, enter
            // tab should move to next cell to the right
            // enter should create a new row or move to next cell down
            else => {},
        }
    }

    fn moveToNextRow(self: *UI, allocator: Allocator, cell_index: CellIndex) ?Cursor {
        const cell = self.getCellFromIndex(cell_index) orelse return null;
        const column = cell.column;
        const table = column.table;

        const current_row_index = cell_index.row_index;

        // Check if this is the last row
        if (current_row_index == table.rows() - 1) {
            // Add new row to table
            table.addRow(allocator) catch return null;
        }

        // Move cursor to next row
        const next_row_index = current_row_index + 1;

        // Calculate position of the next cell
        const table_start_x = @as(f32, @floatFromInt(table.position.left)) * self.units.cell.width;
        const table_start_y = @as(f32, @floatFromInt(table.position.top)) * self.units.cell.height;

        // Find column position within table
        var column_x = table_start_x;
        for (table.columns.items, 0..) |col, col_idx| {
            if (col_idx == cell_index.column_index) {
                break;
            }
            column_x += col.size(self.units).width;
        }

        // Calculate cell Y position by summing heights of previous rows
        var cell_y = table_start_y;
        for (0..next_row_index) |row_i| {
            cell_y += column.data.items[row_i].size(self.units).height;
        }

        return .{
            .text = .{
                .cell_index = CellIndex{
                    .table_index = cell_index.table_index,
                    .column_index = cell_index.column_index,
                    .row_index = next_row_index,
                },
                .pos = Vec2{ column_x, cell_y },
                .char_offset = 0,
            },
        };
    }

    // TODO: include modifiers
    pub fn handleEnter(self: *UI, allocator: Allocator) void {
        if (self.active_cursor) |cursor| {
            switch (cursor) {
                .empty => {
                    // do nothing for now
                },
                .cell => |cell_pos| {
                    const cell = self.getCellFromIndex(cell_pos.cell_index) orelse return;
                    const table = cell.column.table;
                    if (self.moveToNextRow(allocator, cell_pos.cell_index)) |next_cursor| {
                        self.active_cursor = next_cursor;
                        self.shiftTablesDown(table, 1);
                    }
                },
                .text => |text_pos| {
                    const cell = self.getCellFromIndex(text_pos.cell_index) orelse return;
                    const table = cell.column.table;
                    if (self.moveToNextRow(allocator, text_pos.cell_index)) |next_cursor| {
                        self.active_cursor = next_cursor;
                        self.shiftTablesDown(table, 1);
                    }
                },
            }
        }
    }

    fn handleBackspace(self: *UI) void {
        if (self.active_cursor) |cursor| {
            switch (cursor) {
                .empty => {
                    // do nothing for now
                },
                .cell => |cell_pos| {
                    const cell = self.getCellFromIndex(cell_pos.cell_index) orelse return;
                    cell.value.clearRetainingCapacity();
                },
                .text => |text_pos| {
                    const cell = self.getCellFromIndex(text_pos.cell_index) orelse return;
                    if (cell.value.items.len == 0) {
                        return;
                    }
                    _ = cell.value.orderedRemove(text_pos.char_offset);
                    self.active_cursor = .{
                        .text = .{
                            .cell_index = text_pos.cell_index,
                            .pos = .{ text_pos.pos[0] - self.units.text.width, text_pos.pos[1] },
                            .char_offset = if (text_pos.char_offset > 0) text_pos.char_offset - 1 else 0,
                        },
                    };
                },
            }
        }
    }

    pub fn addSelfToScene(self: *UI, allocator: Allocator, scene: *Scene) !void {
        for (self.tables.items) |table| {
            try table.addSelfToScene(scene, allocator, self.units);
        }
        if (self.active_cursor) |cursor| {
            try scene.rects.append(allocator, cursor.getRect(self, .{ 0.5, 0.8, 1.0, 0.8 }));
        }
        if (self.hover_cursor) |cursor| {
            try scene.rects.append(allocator, cursor.getRect(self, .{ 0.7, 0.9, 1.0, 0.4 }));
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

        const cell_pos = self.getCellPosition(p);
        var adjacent_table: ?*Table = null;
        var direction: Direction = .none;
        const empty: EmptyPos = .{
            .grid_pos = cell_pos,
            .grid_size = .{
                .width = 1,
                .height = 1,
            },
        };

        for (self.tables.items) |table| {
            const adj = table.adjacent(cell_pos, self.units);
            if (adj == .down or adj == .right) {
                if (adjacent_table) |_| {
                    // Only possible once left and up are implemented
                    std.log.info("multiple adjacent tables, ignoring", .{});
                    return .{
                        .empty = empty,
                    };
                }
                adjacent_table = table;
                direction = adj;
                break;
            }
        }
        if (adjacent_table) |table| {
            switch (direction) {
                .right => {
                    const matching_row = table.matchingRow(cell_pos, self.units) orelse {
                        std.log.info("no matching row", .{});
                        return .{
                            .empty = empty,
                        };
                    };
                    return .{
                        .empty = .{
                            .grid_pos = .{
                                .top = matching_row.top,
                                .left = cell_pos.left,
                            },
                            .grid_size = .{
                                .width = 1,
                                .height = matching_row.height,
                            },
                        },
                    };
                },
                .down => {
                    const matching_col = table.matchingColumn(cell_pos, self.units) orelse {
                        std.log.info("no matching col", .{});
                        return .{
                            .empty = empty,
                        };
                    };
                    return .{
                        .empty = .{
                            .grid_pos = .{
                                .top = cell_pos.top,
                                .left = matching_col.left,
                            },
                            .grid_size = .{
                                .width = matching_col.width,
                                .height = 1,
                            },
                        },
                    };
                },
                else => {
                    // TODO: handle up and left
                    return .{
                        .empty = empty,
                    };
                },
            }
        }

        // Default to grid cell size if no Cell found
        return .{
            .empty = empty,
        };
    }

    /// Move tables to the right
    fn shiftTablesRight(self: *UI, edited_table: *Table, delta: usize) void {
        if (self.tables.items.len == 0) {
            return;
        }
        const edited_table_size = edited_table.gridSize(self.units);
        const edited_table_top = edited_table.position.top;
        const edited_table_right = edited_table.position.left + edited_table_size.width;
        const edited_table_bottom = edited_table.position.top + edited_table_size.height;

        for (self.tables.items) |table| {
            if (table == edited_table) {
                continue;
            }
            const table_size = table.gridSize(self.units);
            const table_top = table.position.top;
            const table_bottom = table.position.top + table_size.height;
            const intersects_y = !(table_top > edited_table_bottom or table_bottom < edited_table_top);
            if (!intersects_y) {
                continue;
            }
            // Shift any table to the right of edited_table
            if (table.position.left >= edited_table_right) {
                table.position.left += delta;
            }
        }
    }

    /// Move tables downward if row addition
    fn shiftTablesDown(self: *UI, edited_table: *Table, delta: usize) void {
        if (self.tables.items.len == 0) {
            return;
        }
        const edited_table_size = edited_table.gridSize(self.units);
        const edited_table_left = edited_table.position.left;
        const edited_table_right = edited_table.position.left + edited_table_size.width;
        const edited_table_bottom = edited_table.position.top + edited_table_size.height;

        for (self.tables.items) |table| {
            if (table == edited_table) {
                continue;
            }
            const table_size = table.gridSize(self.units);
            const table_left = table.position.left;
            const table_right = table.position.left + table_size.width;
            const table_top = table.position.top;

            const intersects_x = !(table_left > edited_table_right or table_right < edited_table_left);
            if (!intersects_x) {
                continue;
            }
            if (table_top >= edited_table_bottom) {
                table.position.top += delta;
            }
        }
    }

    fn getTextPositionAt(self: *UI, p: Vec2, containing_cell: CellPos) ?TextPos {
        const cell = self.getCellFromIndex(containing_cell.cell_index) orelse return null;
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
                        .cell_index = containing_cell.cell_index,
                        .pos = Vec2{ line_x, line_y },
                        .char_offset = offset,
                    };
                }
            }
        }
        return null;
    }

    fn getCellAt(self: *UI, p: Vec2) ?CellPos {
        for (self.tables.items, 0..) |table, table_idx| {
            const table_start_x = @as(f32, @floatFromInt(table.position.left)) * self.units.cell.width;
            const table_start_y = @as(f32, @floatFromInt(table.position.top)) * self.units.cell.height;

            // Check if position is within table area
            if (p[0] >= table_start_x and p[1] >= table_start_y) {
                var current_x = table_start_x;
                const current_y = table_start_y;

                // Iterate through columns to find which one contains the point
                for (table.columns.items, 0..) |column, col_idx| {
                    const column_size = column.size(self.units);

                    // Check if point is within this column's width
                    if (p[0] >= current_x and p[0] < current_x + column_size.width) {
                        var cell_y = current_y;

                        // Iterate through cells in this column
                        for (column.data.items, 0..) |*cell, row_idx| {
                            const cell_height = cell.size(self.units).height;

                            // Check if point is within this cell's height
                            if (p[1] >= cell_y and p[1] < cell_y + cell_height) {
                                return CellPos{
                                    .cell_index = CellIndex{
                                        .table_index = table_idx,
                                        .column_index = col_idx,
                                        .row_index = row_idx,
                                    },
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

fn isPrintableChar(char_code: u32) bool {
    return char_code >= 32 and char_code <= 126;
}
