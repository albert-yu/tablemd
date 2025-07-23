const std = @import("std");
const sokol = @import("sokol");
const ArrayList = std.ArrayListUnmanaged;
const Allocator = std.mem.Allocator;
const grid = @import("render/dot_grid.zig");
const rect = @import("render/rect.zig");
const text = @import("render/text.zig");
const Vec2 = @import("zm").Vec2f;
const sapp = sokol.app;
const sg = sokol.gfx;
const Keycode = sapp.Keycode;
const table_mod = @import("table.zig");
const scene_mod = @import("render/scene.zig");
const theme = @import("theme.zig");

const RectElement = rect.RectElement;
const TextElement = text.TextElement;
const Size2D = grid.Size;

const GRID_N = grid.GRID_N;
const Color = sg.Color;

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
    /// Not guaranteed to be a valid index,
    /// as it is possible to point past
    /// the last character.
    /// This is mainly used for positioning
    /// the cursor, not indexing into the text.
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

    pub fn handleMouseClick(self: *UI, p: Vec2) void {
        self.active_cursor = self.getCursor(p);
    }

    pub fn handleMouseMove(self: *UI, p: Vec2) void {
        self.hover_cursor = self.getCursor(p);
    }

    fn findAdjacentTable(self: *UI, grid_pos: GridPos) struct { table: ?*Table, direction: Direction, multiple: bool } {
        var adjacent_table: ?*Table = null;
        var direction: Direction = .none;

        for (self.tables.items) |table| {
            const adj = table.adjacent(grid_pos, self.units);
            if (adj != .none) {
                if (adjacent_table) |_| {
                    // Multiple adjacent tables found, return none
                    return .{ .table = null, .direction = .none, .multiple = true };
                }
                adjacent_table = table;
                direction = adj;
            }
        }
        return .{ .table = adjacent_table, .direction = direction, .multiple = false };
    }

    fn insertIntoAdjacentTable(self: *UI, allocator: Allocator, table: *Table, direction: Direction, grid_pos: GridPos, s: []const u8) !void {

        // Find table index
        const table_idx = for (self.tables.items, 0..) |t, idx| {
            if (t == table) break idx;
        } else unreachable;

        switch (direction) {
            .right => {
                const matching_row = table.matchingRow(grid_pos, self.units) orelse {
                    std.log.info("no matching row", .{});
                    return;
                };

                var col = try table.addColumn(allocator);
                const new_y = @as(f32, @floatFromInt(matching_row.top)) * self.units.cell.height;
                const new_x = @as(f32, @floatFromInt(grid_pos.left)) * self.units.cell.width + self.units.text.width;
                const row_i = matching_row.index;
                const cell = &col.data.items[row_i];
                for (s) |char| {
                    try cell.value.append(allocator, char);
                }
                self.active_cursor = .{
                    .text = .{
                        .cell_index = CellIndex{
                            .table_index = table_idx,
                            .column_index = table.columns.items.len - 1, // Last column added
                            .row_index = row_i,
                        },
                        .pos = Vec2{ new_x, new_y },
                        .char_offset = s.len,
                    },
                };
            },
            .down => {
                const matching_col = table.matchingColumn(grid_pos, self.units) orelse {
                    std.log.info("no matching col", .{});
                    return;
                };

                try table.addRow(allocator);
                const row_i = table.rows() - 1;
                const col_i = matching_col.index;
                const cursor_x = @as(f32, @floatFromInt(matching_col.left)) * self.units.cell.width;
                const new_x = cursor_x + self.units.text.width;
                const y = @as(f32, @floatFromInt(grid_pos.top)) * self.units.cell.height;
                const cell = &table.columns.items[col_i].data.items[row_i];
                for (s) |char| {
                    try cell.value.append(allocator, char);
                }
                self.active_cursor = .{
                    .text = .{
                        .cell_index = CellIndex{
                            .table_index = table_idx,
                            .column_index = col_i,
                            .row_index = row_i,
                        },
                        .pos = Vec2{ new_x, y },
                        .char_offset = s.len,
                    },
                };
            },
            .up => {
                const matching_col = table.matchingColumn(grid_pos, self.units) orelse {
                    std.log.info("no matching col", .{});
                    return;
                };

                try table.insertRow(allocator, 0);
                const row_i: usize = 0;
                const col_i = matching_col.index;
                const cursor_x = @as(f32, @floatFromInt(matching_col.left)) * self.units.cell.width;
                const new_x = cursor_x + self.units.text.width;
                const y = @as(f32, @floatFromInt(grid_pos.top)) * self.units.cell.height;
                const cell = &table.columns.items[col_i].data.items[row_i];
                for (s) |char| {
                    try cell.value.append(allocator, char);
                }
                table.position.top -= 1;
                self.active_cursor = .{
                    .text = .{
                        .cell_index = CellIndex{
                            .table_index = table_idx,
                            .column_index = col_i,
                            .row_index = row_i,
                        },
                        .pos = Vec2{ new_x, y },
                        .char_offset = s.len,
                    },
                };
            },
            .left => {
                const matching_row = table.matchingRow(grid_pos, self.units) orelse {
                    std.log.info("no matching row", .{});
                    return;
                };

                var col = try table.insertColumn(allocator, 0);
                const new_y = @as(f32, @floatFromInt(matching_row.top)) * self.units.cell.height;
                const new_x = @as(f32, @floatFromInt(grid_pos.left)) * self.units.cell.width + self.units.text.width;
                const row_i = matching_row.index;
                const cell = &col.data.items[row_i];
                for (s) |char| {
                    try cell.value.append(allocator, char);
                }
                table.position.left -= 1;
                self.active_cursor = .{
                    .text = .{
                        .cell_index = CellIndex{
                            .table_index = table_idx,
                            .column_index = 0, // First column inserted
                            .row_index = row_i,
                        },
                        .pos = Vec2{ new_x, new_y },
                        .char_offset = s.len,
                    },
                };
            },
            else => {},
        }
    }

    pub fn handleChar(self: *UI, allocator: Allocator, char_code: u32) !void {
        if (!isPrintableChar(char_code)) {
            return;
        }
        if (self.active_cursor) |cursor| {
            switch (cursor) {
                .empty => {
                    const adjacent = self.findAdjacentTable(cursor.empty.grid_pos);
                    if (adjacent.multiple) {
                        return;
                    }
                    if (adjacent.table) |table| {
                        const curr_table_width = table.gridSize(self.units).width;
                        const char: u8 = @truncate(char_code);
                        const s = [_]u8{char};
                        try self.insertIntoAdjacentTable(allocator, table, adjacent.direction, cursor.empty.grid_pos, &s);
                        const new_table_width = table.gridSize(self.units).width;
                        if (new_table_width > curr_table_width) {
                            self.shiftTablesRight(table, new_table_width - curr_table_width);
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
                                .char_offset = 1,
                            },
                        };
                        const new_table_width = table.gridSize(self.units).width;
                        self.shiftTablesRight(table, new_table_width);
                    }
                },
                .cell => |cell_pos| {
                    const cell = self.getCellFromIndex(cell_pos.cell_index) orelse return;
                    const curr_table_width = cell.column.table.gridSize(self.units).width;
                    // clear the current text
                    cell.value.clearRetainingCapacity();
                    const char: u8 = @truncate(char_code);
                    try cell.value.insert(allocator, 0, char);
                    const new_table_width = cell.column.table.gridSize(self.units).width;
                    self.active_cursor = .{
                        .text = .{
                            .cell_index = cell_pos.cell_index,
                            .pos = Vec2{ cell_pos.pos[0] + self.units.text.width, cell_pos.pos[1] },
                            .char_offset = 1,
                        },
                    };
                    if (new_table_width > curr_table_width) {
                        self.shiftTablesRight(cell.column.table, new_table_width - curr_table_width);
                    }
                },
                .text => |text_pos| {
                    const cell = self.getCellFromIndex(text_pos.cell_index) orelse return;
                    const curr_table_width = cell.column.table.gridSize(self.units).width;
                    // Convert u32 to u8, handling potential overflow
                    const char: u8 = @truncate(char_code);
                    const new_offset = text_pos.char_offset;
                    try cell.value.insert(allocator, new_offset, char);
                    const new_table_width = cell.column.table.gridSize(self.units).width;
                    const new_x = text_pos.pos[0] + self.units.text.width;
                    self.active_cursor = .{
                        .text = .{
                            .cell_index = text_pos.cell_index,
                            .pos = .{ new_x, text_pos.pos[1] },
                            .char_offset = new_offset + 1,
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
            .BACKSPACE => self.handleBackspace(allocator),
            .ENTER => self.handleEnter(allocator),
            .ESCAPE => self.handleEscape(),
            .LEFT => self.handleArrowLeft(),
            .RIGHT => self.handleArrowRight(),
            .UP => self.handleArrowUp(),
            .DOWN => self.handleArrowDown(),
            // TODO: handle tab
            // tab should move to next cell to the right
            // enter should create a new row or move to next cell down
            else => {},
        }
    }

    pub fn handlePaste(self: *UI, allocator: Allocator, clipboard_text: []const u8) !void {
        if (self.active_cursor) |cursor| {
            switch (cursor) {
                .empty => {
                    const adjacent = self.findAdjacentTable(cursor.empty.grid_pos);
                    if (adjacent.multiple) {
                        return;
                    }
                    if (adjacent.table) |table| {
                        const curr_table_width = table.gridSize(self.units).width;
                        try self.insertIntoAdjacentTable(allocator, table, adjacent.direction, cursor.empty.grid_pos, clipboard_text);
                        const new_table_width = table.gridSize(self.units).width;
                        if (new_table_width > curr_table_width) {
                            self.shiftTablesRight(table, new_table_width - curr_table_width);
                        }
                    } else {
                        // Create a new table at this position
                        const table = try self.addTable(allocator);
                        table.position = cursor.empty.grid_pos;
                        const col = try table.addColumn(allocator);
                        try col.addCell(allocator, "");
                        const cell = &col.data.items[0]; // First cell in the new column
                        // Insert clipboard text at current cursor position
                        for (clipboard_text) |char| {
                            try cell.value.append(allocator, char);
                        }

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
                                .char_offset = clipboard_text.len,
                            },
                        };
                        const new_table_width = table.gridSize(self.units).width;
                        self.shiftTablesRight(table, new_table_width);
                    }
                },
                .cell => |cell_pos| {
                    const cell = self.getCellFromIndex(cell_pos.cell_index) orelse return;
                    const curr_table_width = cell.column.table.gridSize(self.units).width;
                    // Replace entire cell content
                    cell.value.clearRetainingCapacity();
                    for (clipboard_text) |char| {
                        try cell.value.append(allocator, char);
                    }
                    // Move cursor to text mode at the end of pasted content
                    const text_width_offset = @as(f32, @floatFromInt(clipboard_text.len)) * self.units.text.width;
                    const new_table_width = cell.column.table.gridSize(self.units).width;
                    self.active_cursor = .{
                        .text = .{
                            .cell_index = cell_pos.cell_index,
                            .pos = Vec2{ cell_pos.pos[0] + text_width_offset, cell_pos.pos[1] },
                            .char_offset = clipboard_text.len,
                        },
                    };
                    if (new_table_width > curr_table_width) {
                        self.shiftTablesRight(cell.column.table, new_table_width - curr_table_width);
                    }
                },
                .text => |text_pos| {
                    const cell = self.getCellFromIndex(text_pos.cell_index) orelse return;
                    const curr_table_width = cell.column.table.gridSize(self.units).width;
                    // Insert clipboard text at current cursor position
                    var insert_pos = text_pos.char_offset;
                    for (clipboard_text) |char| {
                        try cell.value.insert(allocator, insert_pos, char);
                        insert_pos += 1;
                    }
                    const new_table_width = cell.column.table.gridSize(self.units).width;
                    const text_width_offset = @as(f32, @floatFromInt(clipboard_text.len)) * self.units.text.width;
                    const new_x = text_pos.pos[0] + text_width_offset;
                    self.active_cursor = .{
                        .text = .{
                            .cell_index = text_pos.cell_index,
                            .pos = .{ new_x, text_pos.pos[1] },
                            .char_offset = text_pos.char_offset + clipboard_text.len,
                        },
                    };
                    if (new_table_width > curr_table_width) {
                        self.shiftTablesRight(cell.column.table, new_table_width - curr_table_width);
                    }
                },
            }
        }
    }

    fn handleArrowLeft(self: *UI) void {
        if (self.active_cursor) |cursor| {
            switch (cursor) {
                .empty => {
                    // TODO: figure out the most intuitive way
                    // when colliding with an existing table
                },
                .cell => |cell_pos| {
                    const cell = self.getCellFromIndex(cell_pos.cell_index) orelse return;
                    const table = cell.column.table;
                    const current_col = cell_pos.cell_index.column_index;

                    // Check if we're at the leftmost column
                    if (current_col == 0) {
                        return; // No-op - can't move further left
                    }

                    // Move to the previous column
                    const prev_col_idx = current_col - 1;
                    const prev_column = table.columns.items[prev_col_idx];

                    // Calculate position of the previous cell
                    const table_start_x = @as(f32, @floatFromInt(table.position.left)) * self.units.cell.width;
                    const table_start_y = @as(f32, @floatFromInt(table.position.top)) * self.units.cell.height;

                    var column_x = table_start_x;
                    for (0..prev_col_idx) |col_idx| {
                        column_x += table.columns.items[col_idx].size(self.units).width;
                    }

                    // Calculate cell Y position
                    var cell_y = table_start_y;
                    for (0..cell_pos.cell_index.row_index) |row_i| {
                        cell_y += prev_column.data.items[row_i].size(self.units).height;
                    }

                    self.active_cursor = .{
                        .cell = .{
                            .cell_index = CellIndex{
                                .table_index = cell_pos.cell_index.table_index,
                                .column_index = prev_col_idx,
                                .row_index = cell_pos.cell_index.row_index,
                            },
                            .pos = Vec2{ column_x, cell_y },
                        },
                    };
                },
                .text => |text_pos| {
                    // Check if we're at the beginning of the text
                    if (text_pos.char_offset == 0) {
                        return; // No-op - can't move further left
                    }

                    // Move cursor one character to the left
                    self.active_cursor = .{
                        .text = .{
                            .cell_index = text_pos.cell_index,
                            .pos = .{ text_pos.pos[0] - self.units.text.width, text_pos.pos[1] },
                            .char_offset = text_pos.char_offset - 1,
                        },
                    };
                },
            }
        }
    }

    fn handleArrowRight(self: *UI) void {
        if (self.active_cursor) |cursor| {
            switch (cursor) {
                .empty => {
                    // No-op for empty cursor
                },
                .cell => |cell_pos| {
                    const cell = self.getCellFromIndex(cell_pos.cell_index) orelse return;
                    const table = cell.column.table;
                    const current_col = cell_pos.cell_index.column_index;

                    // Check if we're at the rightmost column
                    if (current_col >= table.columns.items.len - 1) {
                        return; // No-op - can't move further right
                    }

                    // Move to the next column
                    const next_col_idx = current_col + 1;
                    const next_column = table.columns.items[next_col_idx];

                    // Calculate position of the next cell
                    const table_start_x = @as(f32, @floatFromInt(table.position.left)) * self.units.cell.width;
                    const table_start_y = @as(f32, @floatFromInt(table.position.top)) * self.units.cell.height;

                    var column_x = table_start_x;
                    for (0..next_col_idx) |col_idx| {
                        column_x += table.columns.items[col_idx].size(self.units).width;
                    }

                    // Calculate cell Y position
                    var cell_y = table_start_y;
                    for (0..cell_pos.cell_index.row_index) |row_i| {
                        cell_y += next_column.data.items[row_i].size(self.units).height;
                    }

                    self.active_cursor = .{
                        .cell = .{
                            .cell_index = CellIndex{
                                .table_index = cell_pos.cell_index.table_index,
                                .column_index = next_col_idx,
                                .row_index = cell_pos.cell_index.row_index,
                            },
                            .pos = Vec2{ column_x, cell_y },
                        },
                    };
                },
                .text => |text_pos| {
                    const cell = self.getCellFromIndex(text_pos.cell_index) orelse return;

                    // Check if we're at the end of the text
                    if (text_pos.char_offset >= cell.value.items.len) {
                        return; // No-op - can't move further right
                    }

                    // Move cursor one character to the right
                    self.active_cursor = .{
                        .text = .{
                            .cell_index = text_pos.cell_index,
                            .pos = .{ text_pos.pos[0] + self.units.text.width, text_pos.pos[1] },
                            .char_offset = text_pos.char_offset + 1,
                        },
                    };
                },
            }
        }
    }

    fn handleArrowUp(self: *UI) void {
        if (self.active_cursor) |cursor| {
            switch (cursor) {
                .empty => {
                    // No-op for empty cursor
                },
                .cell => |cell_pos| {
                    const cell = self.getCellFromIndex(cell_pos.cell_index) orelse return;
                    const table = cell.column.table;
                    const current_row = cell_pos.cell_index.row_index;

                    // Check if we're at the topmost row
                    if (current_row == 0) {
                        return; // No-op - can't move further up
                    }

                    // Move to the previous row
                    const prev_row_idx = current_row - 1;
                    const column = table.columns.items[cell_pos.cell_index.column_index];

                    // Calculate position of the previous cell
                    const table_start_x = @as(f32, @floatFromInt(table.position.left)) * self.units.cell.width;
                    const table_start_y = @as(f32, @floatFromInt(table.position.top)) * self.units.cell.height;

                    var column_x = table_start_x;
                    for (0..cell_pos.cell_index.column_index) |col_idx| {
                        column_x += table.columns.items[col_idx].size(self.units).width;
                    }

                    // Calculate cell Y position
                    var cell_y = table_start_y;
                    for (0..prev_row_idx) |row_i| {
                        cell_y += column.data.items[row_i].size(self.units).height;
                    }

                    self.active_cursor = .{
                        .cell = .{
                            .cell_index = CellIndex{
                                .table_index = cell_pos.cell_index.table_index,
                                .column_index = cell_pos.cell_index.column_index,
                                .row_index = prev_row_idx,
                            },
                            .pos = Vec2{ column_x, cell_y },
                        },
                    };
                },
                .text => |text_pos| {
                    // FIXME: this is wrong
                    const cell = self.getCellFromIndex(text_pos.cell_index) orelse return;

                    // Check if there are multiple lines in the cell
                    if (countLines(cell) <= 1) {
                        return; // No-op - only one line
                    }

                    // Find current line and column within the text
                    if (findLineAndColumn(cell, text_pos.char_offset)) |line_info| {
                        if (line_info.line == 0) {
                            return; // No-op - already on first line
                        }

                        // Move to the same column on the previous line
                        const target_line = line_info.line - 1;
                        if (findOffsetForLineAndColumn(cell, target_line, line_info.column)) |new_offset| {
                            const new_y = text_pos.pos[1] - self.units.text.height;
                            self.active_cursor = .{
                                .text = .{
                                    .cell_index = text_pos.cell_index,
                                    .pos = .{ text_pos.pos[0], new_y },
                                    .char_offset = new_offset,
                                },
                            };
                        }
                    }
                },
            }
        }
    }

    fn handleArrowDown(self: *UI) void {
        if (self.active_cursor) |cursor| {
            switch (cursor) {
                .empty => {
                    // No-op for empty cursor
                },
                .cell => |cell_pos| {
                    const cell = self.getCellFromIndex(cell_pos.cell_index) orelse return;
                    const table = cell.column.table;
                    const current_row = cell_pos.cell_index.row_index;

                    // Check if we're at the bottommost row
                    if (current_row >= table.rows() - 1) {
                        return; // No-op - can't move further down
                    }

                    // Move to the next row
                    const next_row_idx = current_row + 1;
                    const column = table.columns.items[cell_pos.cell_index.column_index];

                    // Calculate position of the next cell
                    const table_start_x = @as(f32, @floatFromInt(table.position.left)) * self.units.cell.width;
                    const table_start_y = @as(f32, @floatFromInt(table.position.top)) * self.units.cell.height;

                    var column_x = table_start_x;
                    for (0..cell_pos.cell_index.column_index) |col_idx| {
                        column_x += table.columns.items[col_idx].size(self.units).width;
                    }

                    // Calculate cell Y position
                    var cell_y = table_start_y;
                    for (0..next_row_idx) |row_i| {
                        cell_y += column.data.items[row_i].size(self.units).height;
                    }

                    self.active_cursor = .{
                        .cell = .{
                            .cell_index = CellIndex{
                                .table_index = cell_pos.cell_index.table_index,
                                .column_index = cell_pos.cell_index.column_index,
                                .row_index = next_row_idx,
                            },
                            .pos = Vec2{ column_x, cell_y },
                        },
                    };
                },
                .text => |text_pos| {
                    // FIXME: this is wrong
                    const cell = self.getCellFromIndex(text_pos.cell_index) orelse return;

                    // Check if there are multiple lines in the cell
                    const total_lines = countLines(cell);
                    if (total_lines <= 1) {
                        return; // No-op - only one line
                    }

                    // Find current line and column within the text
                    if (findLineAndColumn(cell, text_pos.char_offset)) |line_info| {
                        if (line_info.line >= total_lines - 1) {
                            return; // No-op - already on last line
                        }

                        // Move to the same column on the next line
                        const target_line = line_info.line + 1;
                        if (findOffsetForLineAndColumn(cell, target_line, line_info.column)) |new_offset| {
                            const new_y = text_pos.pos[1] + self.units.text.height;
                            self.active_cursor = .{
                                .text = .{
                                    .cell_index = text_pos.cell_index,
                                    .pos = .{ text_pos.pos[0], new_y },
                                    .char_offset = new_offset,
                                },
                            };
                        }
                    }
                },
            }
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

    fn handleEscape(self: *UI) void {
        self.active_cursor = null;
    }

    fn handleBackspace(self: *UI, allocator: Allocator) void {
        if (self.active_cursor) |cursor| {
            switch (cursor) {
                .empty => {
                    // do nothing for now
                },
                .cell => |cell_pos| {
                    const cell = self.getCellFromIndex(cell_pos.cell_index) orelse return;
                    cell.value.clearRetainingCapacity();
                    const table_idx = cell_pos.cell_index.table_index;
                    const table = self.tables.items[table_idx];
                    if (table.rowIsEmpty(cell_pos.cell_index.row_index)) {
                        table.removeRow(allocator, cell_pos.cell_index.row_index);
                        self.active_cursor = null;
                    }
                },
                .text => |text_pos| {
                    const cell = self.getCellFromIndex(text_pos.cell_index) orelse return;
                    if (cell.value.items.len == 0 or text_pos.char_offset == 0) {
                        return;
                    }
                    const offset_to_remove = text_pos.char_offset - 1;
                    _ = cell.value.orderedRemove(offset_to_remove);

                    const table_idx = text_pos.cell_index.table_index;
                    const column_idx = text_pos.cell_index.column_index;
                    const table = self.tables.items[table_idx];
                    // Check if column now has zero width
                    if (cell.column.gridSize(self.units).width == 0) {
                        // Delete the column and set cursor to null
                        table.removeColumn(allocator, column_idx);
                        self.active_cursor = null;
                    } else if (table.rowIsEmpty(text_pos.cell_index.row_index)) {
                        table.removeRow(allocator, text_pos.cell_index.row_index);
                        self.active_cursor = null;
                    } else {
                        self.active_cursor = .{
                            .text = .{
                                .cell_index = text_pos.cell_index,
                                .pos = .{ text_pos.pos[0] - self.units.text.width, text_pos.pos[1] },
                                .char_offset = offset_to_remove,
                            },
                        };
                    }
                },
            }
        }
    }

    pub fn addSelfToScene(self: *UI, allocator: Allocator, scene: *Scene) !void {
        for (self.tables.items) |table| {
            try table.addSelfToScene(scene, allocator, self.units);
        }
        if (self.active_cursor) |cursor| {
            try scene.rects.append(allocator, cursor.getRect(self, theme.DARK_THEME.active_cursor_color));
        }
        if (self.hover_cursor) |cursor| {
            try scene.rects.append(allocator, cursor.getRect(self, theme.DARK_THEME.hover_cursor_color));
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
        const empty: EmptyPos = .{
            .grid_pos = cell_pos,
            .grid_size = .{
                .width = 1,
                .height = 1,
            },
        };

        const adjacent = self.findAdjacentTable(cell_pos);
        if (adjacent.direction == .none) {
            return .{
                .empty = empty,
            };
        }
        if (adjacent.table) |table| {
            switch (adjacent.direction) {
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
                .up => {
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
                .left => {
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
                else => {},
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
            if (table.position.left >= edited_table.position.left) {
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
            if (table_top >= edited_table.position.top) {
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
                const char_pos = Vec2{ line_x, line_y };
                if (clientRectContains(.{ .pos = char_pos, .size = self.units.text }, p)) {
                    return TextPos{
                        .cell_index = containing_cell.cell_index,
                        .pos = Vec2{ line_x, line_y },
                        .char_offset = offset,
                    };
                }
                line_x += self.units.text.width;
            }
            // allow positioning to the right of the last character
            // so that the user can backspace (delete) the last character
            const last_char_pos = Vec2{ line_x, line_y };
            if (clientRectContains(.{ .pos = last_char_pos, .size = self.units.text }, p)) {
                return TextPos{
                    .cell_index = containing_cell.cell_index,
                    .pos = Vec2{ line_x, line_y },
                    .char_offset = offset,
                };
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

const LineColumn = struct {
    line: usize,
    column: usize,
};

fn findLineAndColumn(cell: *const Cell, char_offset: usize) ?LineColumn {
    var line: usize = 0;
    var column: usize = 0;
    var current_offset: usize = 0;

    while (current_offset < cell.value.items.len and current_offset < char_offset) {
        const char = cell.value.items[current_offset];
        if (char == '\n') {
            line += 1;
            column = 0;
        } else {
            column += 1;
        }
        current_offset += 1;
    }

    return LineColumn{ .line = line, .column = column };
}

fn findOffsetForLineAndColumn(cell: *const Cell, target_line: usize, target_column: usize) ?usize {
    var line: usize = 0;
    var column: usize = 0;
    var offset: usize = 0;

    while (offset < cell.value.items.len) {
        if (line == target_line) {
            if (column == target_column) {
                return offset;
            }
            // If we've reached the end of the target line, return the last position on that line
            if (offset < cell.value.items.len and cell.value.items[offset] == '\n') {
                return offset;
            }
        }

        const char = cell.value.items[offset];
        if (char == '\n') {
            if (line == target_line) {
                // We've reached the end of the target line
                return offset;
            }
            line += 1;
            column = 0;
        } else {
            column += 1;
        }
        offset += 1;
    }

    // If we've reached the end and we're on the target line, return the current offset
    if (line == target_line) {
        return offset;
    }

    return null;
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
