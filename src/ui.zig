const std = @import("std");
const builtin = @import("builtin");
const sokol = @import("sokol");
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const grid = @import("render/dot_grid.zig");
const rect = @import("render/rect.zig");
const Vec2 = @import("zm").Vec2f;
const sapp = sokol.app;
const sg = sokol.gfx;
const Keycode = sapp.Keycode;
const table_mod = @import("table.zig");
const scene_mod = @import("render/scene.zig");
const theme = @import("theme.zig");

const RectElement = rect.RectElement;
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
    /// This is the u8 offset into the cell's value slice.
    /// You cannot assume that incrementing this by 1
    /// will advance to the next character, since some
    /// characters are encoded as multiple bytes.
    ///
    /// Not guaranteed to be a valid index,
    /// as it is possible to point past
    /// the last character. This is so that we
    /// can backspace (delete) the last character.
    char_offset: usize,
};

const TextSelection = struct {
    cell_index: CellIndex,
    pos: Vec2,
    /// Inclusive byte offset into the cell's value slice.
    start_offset: usize,
    /// Exclusive byte offset into the cell's value slice.
    end_offset: usize,
};

const OffsetRange = struct {
    start: usize,
    end: usize,
};

pub const ContextMenuAction = enum {
    delete_row,
    delete_column,
    delete_table,

    pub fn label(self: ContextMenuAction) []const u8 {
        return switch (self) {
            .delete_row => "Delete row",
            .delete_column => "Delete column",
            .delete_table => "Delete table",
        };
    }
};

pub const CONTEXT_MENU_ITEMS = [_]ContextMenuAction{
    .delete_row,
    .delete_column,
    .delete_table,
};

pub const ContextMenu = struct {
    pos: Vec2,
    cell_index: CellIndex,
    hovered_item: ?ContextMenuAction = null,
};

const CursorType = enum {
    empty,
    cell,
    text,
    text_selection,
};

pub const Cursor = union(CursorType) {
    empty: EmptyPos,
    cell: CellPos,
    text: TextPos,
    text_selection: TextSelection,

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
                    const table = ui.tables.items[cell_info.cell_index.table_index];
                    const column = table.columns.items[cell_info.cell_index.column_index];
                    break :blk .{
                        .color = color,
                        .x = cell_info.pos[0],
                        .y = cell_info.pos[1],
                        .width = column.size(units).width,
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
            .text => |text_pos| blk: {
                const cursor_width = units.text.width / 8.0;
                const text_corner = @min(corner, cursor_width * 0.5);
                break :blk .{
                    .color = color,
                    .x = text_pos.pos[0] - cursor_width * 0.5,
                    .y = text_pos.pos[1],
                    .width = cursor_width,
                    .height = units.text.height,
                    .corners = .{ text_corner, text_corner, text_corner, text_corner },
                    .sigma = 1e-6,
                };
            },
            .text_selection => |sel| blk: {
                const char_count = if (ui.getCellFromIndex(sel.cell_index)) |cell|
                    if (sel.start_offset <= sel.end_offset and sel.end_offset <= cell.value.items.len)
                        std.unicode.utf8CountCodepoints(cell.value.items[sel.start_offset..sel.end_offset]) catch (sel.end_offset - sel.start_offset)
                    else
                        0
                else
                    0;
                break :blk .{
                    .color = color,
                    .x = sel.pos[0],
                    .y = sel.pos[1],
                    .width = units.text.width * @as(f32, @floatFromInt(char_count)),
                    .height = units.text.height,
                    .corners = corners,
                    .sigma = 1e-6,
                };
            },
        };
    }
};

pub const UI = struct {
    tables: ArrayList(*Table),
    active_cursor: ?Cursor,
    hover_cursor: ?Cursor,
    context_menu: ?ContextMenu,
    units: Units,

    pub fn init(allocator: Allocator, units: Units) UI {
        return .{
            .tables = ArrayList(*Table).initCapacity(allocator, 0) catch unreachable,
            .active_cursor = null,
            .hover_cursor = null,
            .context_menu = null,
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

    pub fn clearTables(self: *UI, allocator: Allocator) void {
        for (self.tables.items) |table| {
            table.deinit(allocator);
            allocator.destroy(table);
        }
        self.tables.clearRetainingCapacity();
        self.active_cursor = null;
        self.hover_cursor = null;
        self.context_menu = null;
    }

    pub fn removeTable(self: *UI, allocator: Allocator, table_index: usize) void {
        if (table_index >= self.tables.items.len) return;
        var table = self.tables.orderedRemove(table_index);
        table.deinit(allocator);
        allocator.destroy(table);
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

    fn getCellCoordinates(self: *UI, cell_index: CellIndex) ?Vec2 {
        if (cell_index.table_index >= self.tables.items.len) return null;
        const table = self.tables.items[cell_index.table_index];
        if (cell_index.column_index >= table.columns.items.len) return null;
        const column = table.columns.items[cell_index.column_index];
        if (cell_index.row_index >= column.data.items.len) return null;

        var pos_x = @as(f32, @floatFromInt(table.position.left)) * self.units.cell.width;
        for (0..cell_index.column_index) |col_i| {
            pos_x += table.columns.items[col_i].size(self.units).width;
        }
        var pos_y = @as(f32, @floatFromInt(table.position.top)) * self.units.cell.height;
        for (0..cell_index.row_index) |row_i| {
            pos_y += column.data.items[row_i].size(self.units).height;
        }
        return Vec2{ pos_x, pos_y };
    }

    pub fn deleteRow(self: *UI, allocator: Allocator, table_index: usize, row_index: usize) void {
        if (table_index >= self.tables.items.len) return;
        const table = self.tables.items[table_index];
        if (row_index >= table.rows()) return;

        const prev_col_index: usize = if (self.context_menu) |menu|
            if (menu.cell_index.table_index == table_index) menu.cell_index.column_index else 0
        else
            0;

        table.removeRow(allocator, row_index);
        self.hover_cursor = null;
        self.context_menu = null;
        if (table.rows() == 0 or table.cols() == 0) {
            self.removeTable(allocator, table_index);
            self.active_cursor = null;
        } else {
            const clamped_col = @min(prev_col_index, table.cols() - 1);
            const clamped_row = @min(row_index, table.rows() - 1);
            const target_idx = CellIndex{
                .table_index = table_index,
                .column_index = clamped_col,
                .row_index = clamped_row,
            };
            if (self.getCellCoordinates(target_idx)) |pos| {
                self.active_cursor = .{
                    .cell = .{
                        .cell_index = target_idx,
                        .pos = pos,
                    },
                };
            } else {
                self.active_cursor = null;
            }
        }
    }

    pub fn deleteColumn(self: *UI, allocator: Allocator, table_index: usize, column_index: usize) void {
        if (table_index >= self.tables.items.len) return;
        const table = self.tables.items[table_index];
        if (column_index >= table.cols()) return;

        const prev_row_index: usize = if (self.context_menu) |menu|
            if (menu.cell_index.table_index == table_index) menu.cell_index.row_index else 0
        else
            0;

        table.removeColumn(allocator, column_index);
        self.hover_cursor = null;
        self.context_menu = null;
        if (table.cols() == 0 or table.rows() == 0) {
            self.removeTable(allocator, table_index);
            self.active_cursor = null;
        } else {
            const clamped_col = @min(column_index, table.cols() - 1);
            const clamped_row = @min(prev_row_index, table.rows() - 1);
            const target_idx = CellIndex{
                .table_index = table_index,
                .column_index = clamped_col,
                .row_index = clamped_row,
            };
            if (self.getCellCoordinates(target_idx)) |pos| {
                self.active_cursor = .{
                    .cell = .{
                        .cell_index = target_idx,
                        .pos = pos,
                    },
                };
            } else {
                self.active_cursor = null;
            }
        }
    }

    pub fn deleteTable(self: *UI, allocator: Allocator, table_index: usize) void {
        if (table_index >= self.tables.items.len) return;
        self.removeTable(allocator, table_index);
        self.active_cursor = null;
        self.hover_cursor = null;
        self.context_menu = null;
    }

    fn contextMenuPadX(self: UI) f32 {
        return self.units.paddingLeft() * 2.0;
    }

    fn contextMenuItemHeight(self: UI) f32 {
        return self.units.cell.height * 1.2;
    }

    fn contextMenuSize(self: UI) Size2D {
        var max_chars: usize = 0;
        for (CONTEXT_MENU_ITEMS) |item| {
            max_chars = @max(max_chars, item.label().len);
        }
        const width = @as(f32, @floatFromInt(max_chars)) * self.units.text.width + self.contextMenuPadX() * 2.0;
        const height = @as(f32, @floatFromInt(CONTEXT_MENU_ITEMS.len)) * self.contextMenuItemHeight();
        return .{ .width = width, .height = height };
    }

    pub fn getContextMenuActionAt(self: *const UI, p: Vec2) ?ContextMenuAction {
        const menu = self.context_menu orelse return null;
        const menu_size = self.contextMenuSize();
        if (!clientRectContains(.{ .pos = menu.pos, .size = menu_size }, p)) {
            return null;
        }
        const item_height = self.contextMenuItemHeight();
        const rel_y = p[1] - menu.pos[1];
        if (rel_y < 0) return null;
        const idx: usize = @intFromFloat(@floor(rel_y / item_height));
        if (idx >= CONTEXT_MENU_ITEMS.len) return null;
        return CONTEXT_MENU_ITEMS[idx];
    }

    pub fn handleMouseRightClick(self: *UI, p: Vec2) void {
        const cell_info = self.getCellAt(p) orelse {
            self.context_menu = null;
            return;
        };
        self.active_cursor = .{ .cell = cell_info };
        self.hover_cursor = null;
        self.context_menu = .{
            .pos = p,
            .cell_index = cell_info.cell_index,
            .hovered_item = null,
        };
    }

    pub fn handleMouseClick(self: *UI, allocator: Allocator, p: Vec2) void {
        if (self.context_menu) |menu| {
            if (self.getContextMenuActionAt(p)) |action| {
                switch (action) {
                    .delete_row => self.deleteRow(allocator, menu.cell_index.table_index, menu.cell_index.row_index),
                    .delete_column => self.deleteColumn(allocator, menu.cell_index.table_index, menu.cell_index.column_index),
                    .delete_table => self.deleteTable(allocator, menu.cell_index.table_index),
                }
                return;
            }
            self.context_menu = null;
        }
        self.active_cursor = self.getCursor(p);
    }

    pub fn handleMouseHover(self: *UI, p: Vec2) void {
        if (self.context_menu) |*menu| {
            menu.hovered_item = self.getContextMenuActionAt(p);
            self.hover_cursor = null;
            return;
        }
        self.hover_cursor = self.getCursor(p);
    }

    pub fn handleMouseDrag(self: *UI, start_p: Vec2, curr_p: Vec2) void {
        if (self.context_menu != null) return;
        self.hover_cursor = null;
        const cell_info = self.getCellAt(start_p) orelse return;
        const cell = self.getCellFromIndex(cell_info.cell_index) orelse return;
        if (cell.value.items.len == 0) return;

        const offset0 = self.getTextOffsetAtPoint(start_p, cell_info);
        const offset1 = self.getTextOffsetAtPoint(curr_p, cell_info);
        const start_offset = @min(offset0, offset1);
        const end_offset = @max(offset0, offset1);

        const pos = self.getPosForOffset(cell_info, start_offset);
        if (start_offset < end_offset) {
            self.active_cursor = .{
                .text_selection = .{
                    .cell_index = cell_info.cell_index,
                    .pos = pos,
                    .start_offset = start_offset,
                    .end_offset = end_offset,
                },
            };
        } else {
            self.active_cursor = .{
                .text = .{
                    .cell_index = cell_info.cell_index,
                    .pos = pos,
                    .char_offset = start_offset,
                },
            };
        }
    }

    pub fn handleMouseDoubleClick(self: *UI, p: Vec2) void {
        if (self.context_menu != null) {
            self.context_menu = null;
            return;
        }
        const cell_info = self.getCellAt(p) orelse return;
        const cell = self.getCellFromIndex(cell_info.cell_index) orelse return;
        const text = cell.value.items;
        if (text.len == 0) return;

        const text_pos = self.getTextPositionAt(p, cell_info) orelse return;
        const char_range = self.getTextOffsetRangeAtPoint(p, cell_info);
        const anchor_offset: usize = if (char_range.start < char_range.end)
            char_range.start
        else if (text_pos.char_offset < text.len and text[text_pos.char_offset] != '\n')
            text_pos.char_offset
        else if (text_pos.char_offset > 0) blk: {
            const prev = findPrevUtf8CharStart(text, text_pos.char_offset);
            if (text[prev] == '\n') return;
            break :blk prev;
        } else return;

        const target_class = getCharClass(text[anchor_offset]);
        if (target_class == .newline) return;

        var start_offset = anchor_offset;
        while (start_offset > 0) {
            const prev_offset = findPrevUtf8CharStart(text, start_offset);
            if (getCharClass(text[prev_offset]) != target_class) break;
            start_offset = prev_offset;
        }

        var end_offset = findNextUtf8CharStart(text, anchor_offset);
        while (end_offset < text.len) {
            if (getCharClass(text[end_offset]) != target_class) break;
            end_offset = findNextUtf8CharStart(text, end_offset);
        }

        if (start_offset < end_offset) {
            const pos = self.getPosForOffset(cell_info, start_offset);
            self.active_cursor = .{
                .text_selection = .{
                    .cell_index = cell_info.cell_index,
                    .pos = pos,
                    .start_offset = start_offset,
                    .end_offset = end_offset,
                },
            };
        }
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
        } else {
            return error.TableNotFound;
        };

        switch (direction) {
            .right => {
                const matching_row = table.matchingRow(grid_pos, self.units) orelse {
                    std.log.info("no matching row", .{});
                    return;
                };

                var col = try table.addColumn(allocator);
                const new_y = @as(f32, @floatFromInt(matching_row.top)) * self.units.cell.height;
                const padding = self.units.paddingLeft();
                const new_x = @as(f32, @floatFromInt(grid_pos.left)) * self.units.cell.width + padding + self.units.text.width;
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
                const padding = self.units.paddingLeft();
                const new_x = cursor_x + padding + self.units.text.width;
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
                const padding = self.units.paddingLeft();
                const new_x = cursor_x + padding + self.units.text.width;
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
                const padding = self.units.paddingLeft();
                const new_x = @as(f32, @floatFromInt(grid_pos.left)) * self.units.cell.width + padding + self.units.text.width;
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
        self.context_menu = null;
        if (self.active_cursor) |cursor| {
            switch (cursor) {
                .empty => {
                    const adjacent = self.findAdjacentTable(cursor.empty.grid_pos);
                    if (adjacent.multiple) {
                        return;
                    }
                    if (adjacent.table) |table| {
                        const curr_table_width = table.gridSize(self.units).width;
                        var utf8_bytes: [4]u8 = undefined;
                        const utf8_len = std.unicode.utf8Encode(@intCast(char_code), &utf8_bytes) catch return;
                        const utf8_slice = utf8_bytes[0..utf8_len];
                        try self.insertIntoAdjacentTable(allocator, table, adjacent.direction, cursor.empty.grid_pos, utf8_slice);
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
                        var utf8_bytes: [4]u8 = undefined;
                        const utf8_len = try std.unicode.utf8Encode(@intCast(char_code), &utf8_bytes);
                        const cell = &col.data.items[0]; // First cell in the new column
                        for (utf8_bytes[0..utf8_len]) |byte| {
                            try cell.value.append(allocator, byte);
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
                                .pos = Vec2{ cell_x + self.units.paddingLeft() + self.units.text.width, cell_y },
                                .char_offset = utf8_len,
                            },
                        };
                        const new_table_width = table.gridSize(self.units).width;
                        self.shiftTablesRight(table, new_table_width);
                    }
                },
                .cell => |cell_pos| {
                    const cell = self.getCellFromIndex(cell_pos.cell_index) orelse return;
                    const table = self.tables.items[cell_pos.cell_index.table_index];
                    const curr_table_width = table.gridSize(self.units).width;
                    // clear the current text
                    cell.value.clearRetainingCapacity();
                    var utf8_bytes: [4]u8 = undefined;
                    const utf8_len = std.unicode.utf8Encode(@intCast(char_code), &utf8_bytes) catch return;
                    for (utf8_bytes[0..utf8_len]) |byte| {
                        try cell.value.append(allocator, byte);
                    }
                    const new_table_width = table.gridSize(self.units).width;
                    const padding = self.units.paddingLeft();
                    self.active_cursor = .{
                        .text = .{
                            .cell_index = cell_pos.cell_index,
                            .pos = Vec2{ cell_pos.pos[0] + padding + self.units.text.width, cell_pos.pos[1] },
                            .char_offset = utf8_len,
                        },
                    };
                    if (new_table_width > curr_table_width) {
                        self.shiftTablesRight(table, new_table_width - curr_table_width);
                    }
                },
                .text => |text_pos| {
                    const cell = self.getCellFromIndex(text_pos.cell_index) orelse return;
                    const table = self.tables.items[text_pos.cell_index.table_index];
                    const curr_table_width = table.gridSize(self.units).width;
                    var utf8_bytes: [4]u8 = undefined;
                    const utf8_len = std.unicode.utf8Encode(@intCast(char_code), &utf8_bytes) catch return;
                    const new_offset = text_pos.char_offset;
                    for (utf8_bytes[0..utf8_len], 0..) |byte, i| {
                        try cell.value.insert(allocator, new_offset + i, byte);
                    }
                    const new_table_width = table.gridSize(self.units).width;
                    const new_x = text_pos.pos[0] + self.units.text.width;
                    self.active_cursor = .{
                        .text = .{
                            .cell_index = text_pos.cell_index,
                            .pos = .{ new_x, text_pos.pos[1] },
                            .char_offset = new_offset + utf8_len,
                        },
                    };
                    if (new_table_width > curr_table_width) {
                        self.shiftTablesRight(table, new_table_width - curr_table_width);
                    }
                },
                .text_selection => |sel| {
                    const cell = self.getCellFromIndex(sel.cell_index) orelse return;
                    const table = self.tables.items[sel.cell_index.table_index];
                    const curr_table_width = table.gridSize(self.units).width;
                    if (sel.start_offset < sel.end_offset and sel.end_offset <= cell.value.items.len) {
                        const bytes_to_remove = sel.end_offset - sel.start_offset;
                        for (0..bytes_to_remove) |_| {
                            _ = cell.value.orderedRemove(sel.start_offset);
                        }
                    }
                    var utf8_bytes: [4]u8 = undefined;
                    const utf8_len = std.unicode.utf8Encode(@intCast(char_code), &utf8_bytes) catch return;
                    const new_offset = sel.start_offset;
                    for (utf8_bytes[0..utf8_len], 0..) |byte, i| {
                        try cell.value.insert(allocator, new_offset + i, byte);
                    }
                    const new_table_width = table.gridSize(self.units).width;
                    const new_x = sel.pos[0] + self.units.text.width;
                    self.active_cursor = .{
                        .text = .{
                            .cell_index = sel.cell_index,
                            .pos = .{ new_x, sel.pos[1] },
                            .char_offset = new_offset + utf8_len,
                        },
                    };
                    if (new_table_width > curr_table_width) {
                        self.shiftTablesRight(table, new_table_width - curr_table_width);
                    }
                },
            }
        }
    }

    pub fn handleKeyDown(self: *UI, allocator: Allocator, key_code: Keycode, modifiers: u32) void {
        if (key_code != .ESCAPE) {
            self.context_menu = null;
        }
        switch (key_code) {
            .BACKSPACE, .DELETE => self.handleBackspace(allocator),
            .ENTER => self.handleEnter(allocator, modifiers),
            .ESCAPE => self.handleEscape(),
            .LEFT => self.handleArrowLeft(),
            .RIGHT => self.handleArrowRight(),
            .UP => self.handleArrowUp(),
            .DOWN => self.handleArrowDown(),
            .TAB => self.handleTab(modifiers),
            else => {},
        }
    }

    pub fn handleCopy(self: *UI, allocator: Allocator) ![]const u8 {
        var str_builder = try ArrayList(u8).initCapacity(allocator, 0);
        if (self.active_cursor) |cursor| {
            switch (cursor) {
                .empty => {},
                .cell => |cell_pos| {
                    const cell = self.getCellFromIndex(cell_pos.cell_index) orelse return error.CellNotFound;
                    const cell_content = cell.value.items;
                    try str_builder.appendSlice(allocator, cell_content);
                },
                .text => {},
                .text_selection => |sel| {
                    const cell = self.getCellFromIndex(sel.cell_index) orelse return error.CellNotFound;
                    if (sel.start_offset < sel.end_offset and sel.end_offset <= cell.value.items.len) {
                        try str_builder.appendSlice(allocator, cell.value.items[sel.start_offset..sel.end_offset]);
                    }
                },
            }
        }
        return str_builder.toOwnedSlice(allocator);
    }

    pub fn handlePaste(self: *UI, allocator: Allocator, clipboard_text: []const u8) !void {
        self.context_menu = null;
        if (self.active_cursor) |cursor| {
            switch (cursor) {
                .empty => {
                    const adjacent = self.findAdjacentTable(cursor.empty.grid_pos);
                    if (adjacent.multiple) {
                        return;
                    }
                    if (adjacent.table) |table| {
                        const curr_table_size = table.gridSize(self.units);
                        try self.insertIntoAdjacentTable(allocator, table, adjacent.direction, cursor.empty.grid_pos, clipboard_text);
                        const new_table_size = table.gridSize(self.units);
                        if (new_table_size.width > curr_table_size.width) {
                            self.shiftTablesRight(table, new_table_size.width - curr_table_size.width);
                        }
                        if (new_table_size.height > curr_table_size.height) {
                            self.shiftTablesDown(table, new_table_size.height - curr_table_size.height);
                        }
                    } else {
                        // Create a new table at this position
                        const table = try self.addTable(allocator);
                        table.position = cursor.empty.grid_pos;
                        const col = try table.addColumn(allocator);
                        try col.addCell(allocator, "");
                        const cell = &col.data.items[0]; // First cell in the new column
                        try cell.value.appendSlice(allocator, clipboard_text);

                        // Set cursor to text position after the inserted text
                        const cell_x = @as(f32, @floatFromInt(table.position.left)) * self.units.cell.width;
                        const cell_y = @as(f32, @floatFromInt(table.position.top)) * self.units.cell.height;
                        const char_count = std.unicode.utf8CountCodepoints(clipboard_text) catch clipboard_text.len;
                        const text_width_offset = @as(f32, @floatFromInt(char_count)) * self.units.text.width;
                        const table_idx = self.tables.items.len - 1; // Last table added
                        self.active_cursor = .{
                            .text = .{
                                .cell_index = CellIndex{
                                    .table_index = table_idx,
                                    .column_index = 0,
                                    .row_index = 0,
                                },
                                .pos = Vec2{ cell_x + self.units.paddingLeft() + text_width_offset, cell_y },
                                .char_offset = clipboard_text.len,
                            },
                        };
                        const new_table_size = table.gridSize(self.units);
                        self.shiftTablesRight(table, new_table_size.width);
                        if (new_table_size.height > 1) {
                            self.shiftTablesDown(table, new_table_size.height - 1);
                        }
                    }
                },
                .cell => |cell_pos| {
                    const cell = self.getCellFromIndex(cell_pos.cell_index) orelse return;
                    const table = self.tables.items[cell_pos.cell_index.table_index];
                    const curr_table_size = table.gridSize(self.units);
                    // Replace entire cell content
                    cell.value.clearRetainingCapacity();
                    for (clipboard_text) |char| {
                        try cell.value.append(allocator, char);
                    }
                    // Move cursor to text mode at the end of pasted content
                    const char_count = std.unicode.utf8CountCodepoints(clipboard_text) catch clipboard_text.len;
                    const text_width_offset = @as(f32, @floatFromInt(char_count)) * self.units.text.width;
                    const new_table_size = table.gridSize(self.units);
                    const padding = self.units.paddingLeft();
                    self.active_cursor = .{
                        .text = .{
                            .cell_index = cell_pos.cell_index,
                            .pos = Vec2{ cell_pos.pos[0] + padding + text_width_offset, cell_pos.pos[1] },
                            .char_offset = clipboard_text.len,
                        },
                    };
                    if (new_table_size.width > curr_table_size.width) {
                        self.shiftTablesRight(table, new_table_size.width - curr_table_size.width);
                    }
                    if (new_table_size.height > curr_table_size.height) {
                        self.shiftTablesDown(table, new_table_size.height - curr_table_size.height);
                    }
                },
                .text => |text_pos| {
                    const cell = self.getCellFromIndex(text_pos.cell_index) orelse return;
                    const table = self.tables.items[text_pos.cell_index.table_index];
                    const curr_table_size = table.gridSize(self.units);
                    // Insert clipboard text at current cursor position
                    var insert_pos = text_pos.char_offset;
                    for (clipboard_text) |char| {
                        try cell.value.insert(allocator, insert_pos, char);
                        insert_pos += 1;
                    }
                    const new_table_size = table.gridSize(self.units);
                    const char_count = std.unicode.utf8CountCodepoints(clipboard_text) catch clipboard_text.len;
                    const text_width_offset = @as(f32, @floatFromInt(char_count)) * self.units.text.width;
                    const new_x = text_pos.pos[0] + text_width_offset;
                    self.active_cursor = .{
                        .text = .{
                            .cell_index = text_pos.cell_index,
                            .pos = .{ new_x, text_pos.pos[1] },
                            .char_offset = text_pos.char_offset + clipboard_text.len,
                        },
                    };
                    if (new_table_size.width > curr_table_size.width) {
                        self.shiftTablesRight(table, new_table_size.width - curr_table_size.width);
                    }
                    if (new_table_size.height > curr_table_size.height) {
                        self.shiftTablesDown(table, new_table_size.height - curr_table_size.height);
                    }
                },
                .text_selection => |sel| {
                    const cell = self.getCellFromIndex(sel.cell_index) orelse return;
                    const table = self.tables.items[sel.cell_index.table_index];
                    const curr_table_size = table.gridSize(self.units);
                    if (sel.start_offset < sel.end_offset and sel.end_offset <= cell.value.items.len) {
                        const bytes_to_remove = sel.end_offset - sel.start_offset;
                        for (0..bytes_to_remove) |_| {
                            _ = cell.value.orderedRemove(sel.start_offset);
                        }
                    }
                    var insert_pos = sel.start_offset;
                    for (clipboard_text) |char| {
                        try cell.value.insert(allocator, insert_pos, char);
                        insert_pos += 1;
                    }
                    const new_table_size = table.gridSize(self.units);
                    const char_count = std.unicode.utf8CountCodepoints(clipboard_text) catch clipboard_text.len;
                    const text_width_offset = @as(f32, @floatFromInt(char_count)) * self.units.text.width;
                    const new_x = sel.pos[0] + text_width_offset;
                    self.active_cursor = .{
                        .text = .{
                            .cell_index = sel.cell_index,
                            .pos = .{ new_x, sel.pos[1] },
                            .char_offset = sel.start_offset + clipboard_text.len,
                        },
                    };
                    if (new_table_size.width > curr_table_size.width) {
                        self.shiftTablesRight(table, new_table_size.width - curr_table_size.width);
                    }
                    if (new_table_size.height > curr_table_size.height) {
                        self.shiftTablesDown(table, new_table_size.height - curr_table_size.height);
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
                    const table = self.tables.items[cell_pos.cell_index.table_index];
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
                    const cell = self.getCellFromIndex(text_pos.cell_index) orelse return;
                    if (cell.value.items.len == 0 or text_pos.char_offset == 0) {
                        return;
                    }

                    // Find the start of the previous UTF-8 character
                    const prev_char_start = findPrevUtf8CharStart(cell.value.items, text_pos.char_offset);

                    // Move cursor one character to the left
                    self.active_cursor = .{
                        .text = .{
                            .cell_index = text_pos.cell_index,
                            .pos = .{ text_pos.pos[0] - self.units.text.width, text_pos.pos[1] },
                            .char_offset = prev_char_start,
                        },
                    };
                },
                .text_selection => |sel| {
                    self.active_cursor = .{
                        .text = .{
                            .cell_index = sel.cell_index,
                            .pos = sel.pos,
                            .char_offset = sel.start_offset,
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
                    const table = self.tables.items[cell_pos.cell_index.table_index];
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

                    // Find the start of the next UTF-8 character
                    const next_char_start = findNextUtf8CharStart(cell.value.items, text_pos.char_offset);

                    // Move cursor one character to the right
                    self.active_cursor = .{
                        .text = .{
                            .cell_index = text_pos.cell_index,
                            .pos = .{ text_pos.pos[0] + self.units.text.width, text_pos.pos[1] },
                            .char_offset = next_char_start,
                        },
                    };
                },
                .text_selection => |sel| {
                    const cell = self.getCellFromIndex(sel.cell_index) orelse return;
                    const char_count = if (sel.start_offset <= sel.end_offset and sel.end_offset <= cell.value.items.len)
                        std.unicode.utf8CountCodepoints(cell.value.items[sel.start_offset..sel.end_offset]) catch (sel.end_offset - sel.start_offset)
                    else
                        0;
                    self.active_cursor = .{
                        .text = .{
                            .cell_index = sel.cell_index,
                            .pos = .{ sel.pos[0] + @as(f32, @floatFromInt(char_count)) * self.units.text.width, sel.pos[1] },
                            .char_offset = sel.end_offset,
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
                    const table = self.tables.items[cell_pos.cell_index.table_index];
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
                .text_selection => |sel| {
                    self.active_cursor = .{
                        .text = .{
                            .cell_index = sel.cell_index,
                            .pos = sel.pos,
                            .char_offset = sel.start_offset,
                        },
                    };
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
                    const table = self.tables.items[cell_pos.cell_index.table_index];
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
                .text_selection => |sel| {
                    self.active_cursor = .{
                        .text = .{
                            .cell_index = sel.cell_index,
                            .pos = sel.pos,
                            .char_offset = sel.start_offset,
                        },
                    };
                },
            }
        }
    }

    fn moveToNextRow(self: *UI, allocator: Allocator, cell_index: CellIndex) ?Cursor {
        const table = self.tables.items[cell_index.table_index];
        const column = table.columns.items[cell_index.column_index];

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

        const padding = self.units.paddingLeft();
        return .{
            .text = .{
                .cell_index = CellIndex{
                    .table_index = cell_index.table_index,
                    .column_index = cell_index.column_index,
                    .row_index = next_row_index,
                },
                .pos = Vec2{ column_x + padding, cell_y },
                .char_offset = 0,
            },
        };
    }

    fn setCursorToCell(self: *UI, target_cell_index: CellIndex) void {
        const table = self.tables.items[target_cell_index.table_index];
        const column = table.columns.items[target_cell_index.column_index];

        // Calculate table start position
        const table_start_x = @as(f32, @floatFromInt(table.position.left)) * self.units.cell.width;
        const table_start_y = @as(f32, @floatFromInt(table.position.top)) * self.units.cell.height;

        // Calculate column X position by summing widths of previous columns
        var column_x = table_start_x;
        for (0..target_cell_index.column_index) |col_idx| {
            column_x += table.columns.items[col_idx].size(self.units).width;
        }

        // Calculate cell Y position by summing heights of previous rows in this column
        var cell_y = table_start_y;
        for (0..target_cell_index.row_index) |row_i| {
            cell_y += column.data.items[row_i].size(self.units).height;
        }

        const padding = self.units.paddingLeft();
        self.active_cursor = .{
            .text = .{
                .cell_index = target_cell_index,
                .pos = Vec2{ column_x + padding, cell_y },
                .char_offset = 0,
            },
        };
    }

    fn prevCell(self: *UI, cell_index: CellIndex) void {
        const table = self.tables.items[cell_index.table_index];
        const current_col = cell_index.column_index;

        // Check if we're at the leftmost column
        if (current_col == 0) {
            // Go to the last column of the previous row
            if (cell_index.row_index == 0) {
                return; // Can't tab further - at the first cell of the table
            }

            const prev_row_idx = cell_index.row_index - 1;
            const last_col_idx = table.columns.items.len - 1;
            self.setCursorToCell(CellIndex{
                .table_index = cell_index.table_index,
                .column_index = last_col_idx,
                .row_index = prev_row_idx,
            });
        } else {
            // Move to the previous column to the left
            const prev_col_idx = current_col - 1;
            self.setCursorToCell(CellIndex{
                .table_index = cell_index.table_index,
                .column_index = prev_col_idx,
                .row_index = cell_index.row_index,
            });
        }
    }

    fn nextCell(self: *UI, cell_index: CellIndex) void {
        const table = self.tables.items[cell_index.table_index];
        const current_col = cell_index.column_index;

        // Check if we're at the rightmost column
        if (current_col == table.columns.items.len - 1) {
            // Go to the first column of the next row
            const next_row_idx = cell_index.row_index + 1;

            // Check if we need to add a new row
            if (next_row_idx >= table.rows()) {
                return; // Can't tab further - at the last cell of the table
            }

            self.setCursorToCell(CellIndex{
                .table_index = cell_index.table_index,
                .column_index = 0, // First column
                .row_index = next_row_idx,
            });
        } else {
            // Move to the next column to the right
            const next_col_idx = current_col + 1;
            self.setCursorToCell(CellIndex{
                .table_index = cell_index.table_index,
                .column_index = next_col_idx,
                .row_index = cell_index.row_index,
            });
        }
    }

    fn handleTab(self: *UI, modifiers: u32) void {
        if (self.active_cursor) |cursor| {
            switch (cursor) {
                .empty => {
                    // No-op for empty cursor
                },
                .cell => |cell_pos| {
                    if (modifiers & sapp.modifier_shift != 0) {
                        self.prevCell(cell_pos.cell_index);
                    } else {
                        self.nextCell(cell_pos.cell_index);
                    }
                },
                .text => |text_pos| {
                    if (modifiers & sapp.modifier_shift != 0) {
                        self.prevCell(text_pos.cell_index);
                    } else {
                        self.nextCell(text_pos.cell_index);
                    }
                },
                .text_selection => |sel| {
                    if (modifiers & sapp.modifier_shift != 0) {
                        self.prevCell(sel.cell_index);
                    } else {
                        self.nextCell(sel.cell_index);
                    }
                },
            }
        }
    }

    pub fn handleEnter(self: *UI, allocator: Allocator, modifiers: u32) void {
        const ENABLE_NEWLINE = false;
        if (modifiers & sapp.modifier_shift != 0 and ENABLE_NEWLINE) {
            self.insertNewline(allocator);
            return;
        }
        if (self.active_cursor) |cursor| {
            switch (cursor) {
                .empty => {
                    // do nothing for now
                },
                .cell => |cell_pos| {
                    const table = self.tables.items[cell_pos.cell_index.table_index];
                    if (self.moveToNextRow(allocator, cell_pos.cell_index)) |next_cursor| {
                        self.active_cursor = next_cursor;
                        self.shiftTablesDown(table, 1);
                    }
                },
                .text => |text_pos| {
                    const table = self.tables.items[text_pos.cell_index.table_index];
                    if (self.moveToNextRow(allocator, text_pos.cell_index)) |next_cursor| {
                        self.active_cursor = next_cursor;
                        self.shiftTablesDown(table, 1);
                    }
                },
                .text_selection => |sel| {
                    const table = self.tables.items[sel.cell_index.table_index];
                    if (self.moveToNextRow(allocator, sel.cell_index)) |next_cursor| {
                        self.active_cursor = next_cursor;
                        self.shiftTablesDown(table, 1);
                    }
                },
            }
        }
    }

    fn insertNewline(self: *UI, allocator: Allocator) void {
        if (self.active_cursor) |cursor| {
            switch (cursor) {
                .empty => {
                    // do nothing for now
                },
                .cell => |cell_pos| {
                    const cell = self.getCellFromIndex(cell_pos.cell_index) orelse return;
                    // Insert newline at the beginning of the cell
                    cell.value.insert(allocator, 0, '\n') catch return;

                    // Move cursor to text position after the newline
                    const padding = self.units.paddingLeft();
                    self.active_cursor = .{
                        .text = .{
                            .cell_index = cell_pos.cell_index,
                            .pos = Vec2{ cell_pos.pos[0] + padding, cell_pos.pos[1] + self.units.text.height },
                            .char_offset = 1, // After the newline character
                        },
                    };
                },
                .text => |text_pos| {
                    const cell = self.getCellFromIndex(text_pos.cell_index) orelse return;
                    // Insert newline at current cursor position
                    cell.value.insert(allocator, text_pos.char_offset, '\n') catch return;

                    // Move cursor to the next line, at the beginning
                    const padding = self.units.paddingLeft();
                    self.active_cursor = .{
                        .text = .{
                            .cell_index = text_pos.cell_index,
                            .pos = Vec2{ self.getCellLeftPosition(text_pos.cell_index) + padding, text_pos.pos[1] + self.units.text.height },
                            .char_offset = text_pos.char_offset + 1, // After the newline character
                        },
                    };
                },
                .text_selection => |sel| {
                    const cell = self.getCellFromIndex(sel.cell_index) orelse return;
                    if (sel.start_offset < sel.end_offset and sel.end_offset <= cell.value.items.len) {
                        const bytes_to_remove = sel.end_offset - sel.start_offset;
                        for (0..bytes_to_remove) |_| {
                            _ = cell.value.orderedRemove(sel.start_offset);
                        }
                    }
                    cell.value.insert(allocator, sel.start_offset, '\n') catch return;
                    const padding = self.units.paddingLeft();
                    self.active_cursor = .{
                        .text = .{
                            .cell_index = sel.cell_index,
                            .pos = Vec2{ self.getCellLeftPosition(sel.cell_index) + padding, sel.pos[1] + self.units.text.height },
                            .char_offset = sel.start_offset + 1,
                        },
                    };
                },
            }
        }
    }

    fn handleEscape(self: *UI) void {
        if (self.context_menu != null) {
            self.context_menu = null;
            return;
        }
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
                        if (table.rows() == 0 or table.cols() == 0) {
                            self.removeTable(allocator, table_idx);
                        }
                        self.active_cursor = null;
                    }
                },
                .text => |text_pos| {
                    const cell = self.getCellFromIndex(text_pos.cell_index) orelse return;
                    if (cell.value.items.len == 0 or text_pos.char_offset == 0) {
                        return;
                    }

                    // Check if cursor is at the beginning of a line and there's a line above it
                    if (findLineAndColumn(cell, text_pos.char_offset)) |line_info| {
                        if (line_info.column == 0 and line_info.line > 0) {
                            // We're at the beginning of a line with a line above
                            // Find the end of the previous line
                            const prev_line_end_offset = findEndOfLine(cell, line_info.line - 1);

                            // Remove the newline character
                            _ = cell.value.orderedRemove(prev_line_end_offset);

                            // Move cursor to the end of the previous line
                            const prev_line_info = findLineAndColumn(cell, prev_line_end_offset) orelse return;
                            const cell_left_x = self.getCellLeftPosition(text_pos.cell_index);
                            const padding = self.units.paddingLeft();
                            const new_x = cell_left_x + padding + @as(f32, @floatFromInt(prev_line_info.column)) * self.units.text.width;
                            const new_y = text_pos.pos[1] - self.units.text.height;

                            self.active_cursor = .{
                                .text = .{
                                    .cell_index = text_pos.cell_index,
                                    .pos = .{ new_x, new_y },
                                    .char_offset = prev_line_end_offset,
                                },
                            };
                            return;
                        }
                    }

                    // Find the start of the previous UTF-8 character
                    const prev_char_start = findPrevUtf8CharStart(cell.value.items, text_pos.char_offset);

                    // Remove all bytes of the previous character
                    const bytes_to_remove = text_pos.char_offset - prev_char_start;
                    for (0..bytes_to_remove) |_| {
                        _ = cell.value.orderedRemove(prev_char_start);
                    }

                    const table_idx = text_pos.cell_index.table_index;
                    const column_idx = text_pos.cell_index.column_index;
                    const table = self.tables.items[table_idx];
                    const column = table.columns.items[column_idx];
                    // Check if column now has zero width
                    if (column.gridSize(self.units).width == 0) {
                        // Delete the column and set cursor to null
                        table.removeColumn(allocator, column_idx);
                        if (table.cols() == 0 or table.rows() == 0) {
                            self.removeTable(allocator, table_idx);
                        }
                        self.active_cursor = null;
                    } else if (table.rowIsEmpty(text_pos.cell_index.row_index)) {
                        table.removeRow(allocator, text_pos.cell_index.row_index);
                        if (table.rows() == 0 or table.cols() == 0) {
                            self.removeTable(allocator, table_idx);
                        }
                        self.active_cursor = null;
                    } else {
                        self.active_cursor = .{
                            .text = .{
                                .cell_index = text_pos.cell_index,
                                .pos = .{ text_pos.pos[0] - self.units.text.width, text_pos.pos[1] },
                                .char_offset = prev_char_start,
                            },
                        };
                    }
                },
                .text_selection => |sel| {
                    const cell = self.getCellFromIndex(sel.cell_index) orelse return;
                    if (sel.start_offset >= sel.end_offset or sel.end_offset > cell.value.items.len) {
                        return;
                    }

                    const bytes_to_remove = sel.end_offset - sel.start_offset;
                    for (0..bytes_to_remove) |_| {
                        _ = cell.value.orderedRemove(sel.start_offset);
                    }

                    const table_idx = sel.cell_index.table_index;
                    const column_idx = sel.cell_index.column_index;
                    const table = self.tables.items[table_idx];
                    const column = table.columns.items[column_idx];
                    if (column.gridSize(self.units).width == 0) {
                        table.removeColumn(allocator, column_idx);
                        if (table.cols() == 0 or table.rows() == 0) {
                            self.removeTable(allocator, table_idx);
                        }
                        self.active_cursor = null;
                    } else if (table.rowIsEmpty(sel.cell_index.row_index)) {
                        table.removeRow(allocator, sel.cell_index.row_index);
                        if (table.rows() == 0 or table.cols() == 0) {
                            self.removeTable(allocator, table_idx);
                        }
                        self.active_cursor = null;
                    } else {
                        self.active_cursor = .{
                            .text = .{
                                .cell_index = sel.cell_index,
                                .pos = sel.pos,
                                .char_offset = sel.start_offset,
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
        const current_theme = theme.current();
        if (self.active_cursor) |cursor| {
            try scene.rects.append(allocator, cursor.getRect(self, current_theme.active_cursor_color));
            const active_cell_index: ?CellIndex = switch (cursor) {
                .empty => null,
                .cell => |cell_pos| cell_pos.cell_index,
                .text => |text_pos| text_pos.cell_index,
                .text_selection => |sel| sel.cell_index,
            };
            if (active_cell_index) |cell_index| {
                if (cell_index.table_index < self.tables.items.len) {
                    const table = self.tables.items[cell_index.table_index];
                    try table.addCellBorderToScene(
                        scene,
                        allocator,
                        self.units,
                        cell_index.column_index,
                        cell_index.row_index,
                        current_theme.edited_cell_border_color,
                    );
                }
            }
        }
        if (self.hover_cursor) |cursor| {
            try scene.rects.append(allocator, cursor.getRect(self, current_theme.hover_cursor_color));
        }
    }

    pub fn addContextMenuToScene(self: *UI, allocator: Allocator, scene: *Scene) !void {
        const menu = self.context_menu orelse return;
        const current_theme = theme.current();
        const menu_size = self.contextMenuSize();
        const item_height = self.contextMenuItemHeight();
        const pad_x = self.contextMenuPadX();
        const pad_y = (item_height - self.units.cell.height) * 0.5;
        const corner: f32 = 1.0 / 512.0;
        const corners = .{ corner, corner, corner, corner };

        // Drop shadow
        try scene.rects.append(allocator, .{
            .color = current_theme.context_menu_shadow_color,
            .x = menu.pos[0],
            .y = menu.pos[1] + self.units.cell.height * 0.08,
            .width = menu_size.width,
            .height = menu_size.height,
            .corners = corners,
            .sigma = self.units.cell.height * 0.15,
        });

        // Menu background
        try scene.rects.append(allocator, .{
            .color = current_theme.context_menu_background_color,
            .x = menu.pos[0],
            .y = menu.pos[1],
            .width = menu_size.width,
            .height = menu_size.height,
            .corners = corners,
            .sigma = 1e-6,
        });

        for (CONTEXT_MENU_ITEMS, 0..) |item, i| {
            const item_y = menu.pos[1] + @as(f32, @floatFromInt(i)) * item_height;
            if (menu.hovered_item == item) {
                const is_top = i == 0;
                const is_bottom = i + 1 == CONTEXT_MENU_ITEMS.len;
                const item_corners: [4]f32 = .{
                    if (is_top) corner else 0.0,
                    if (is_top) corner else 0.0,
                    if (is_bottom) corner else 0.0,
                    if (is_bottom) corner else 0.0,
                };
                try scene.rects.append(allocator, .{
                    .color = current_theme.hover_cursor_color,
                    .x = menu.pos[0],
                    .y = item_y,
                    .width = menu_size.width,
                    .height = item_height,
                    .corners = item_corners,
                    .sigma = 1e-6,
                });
            }

            if (i + 1 < CONTEXT_MENU_ITEMS.len) {
                try scene.lines.append(allocator, .{
                    .p0 = .{ menu.pos[0], item_y + item_height },
                    .p1 = .{ menu.pos[0] + menu_size.width, item_y + item_height },
                    .color = current_theme.context_menu_border_color,
                });
            }

            try scene.texts.append(allocator, .{
                .text = item.label(),
                .x = menu.pos[0] + pad_x,
                .y = item_y + pad_y + self.units.cell.height,
            });
        }

        try table_mod.addRoundedRectLines(
            scene,
            allocator,
            menu.pos[0],
            menu.pos[1],
            menu_size.width,
            menu_size.height,
            corner,
            current_theme.context_menu_border_color,
        );
    }

    fn getCellLeftPosition(self: *UI, cell_index: CellIndex) f32 {
        const table = self.tables.items[cell_index.table_index];
        const table_start_x = @as(f32, @floatFromInt(table.position.left)) * self.units.cell.width;
        var cell_left_x = table_start_x;
        for (0..cell_index.column_index) |col_idx| {
            cell_left_x += table.columns.items[col_idx].size(self.units).width;
        }
        return cell_left_x;
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
        const padding = self.units.paddingLeft();
        var x: f32 = containing_cell.pos[0] + padding;
        const half_w = self.units.text.width * 0.5;
        for (0..lines) |target_line| {
            var line_x = x;
            const line_y = containing_cell.pos[1] + self.units.cell.height * @as(f32, @floatFromInt(target_line));
            while (offset < cell.value.items.len) {
                const char = cell.value.items[offset];

                // Check if click position is closest to the boundary before the current character
                const char_pos = Vec2{ line_x - half_w, line_y };
                if (clientRectContains(.{ .pos = char_pos, .size = self.units.text }, p)) {
                    return TextPos{
                        .cell_index = containing_cell.cell_index,
                        .pos = Vec2{ line_x, line_y },
                        .char_offset = offset,
                    };
                }

                if (char == '\n') {
                    // reset x to start for next line
                    x = containing_cell.pos[0] + padding;
                    offset += 1;
                    break;
                }

                // Move to next UTF-8 character (advance visually by one character width)
                line_x += self.units.text.width;
                offset = findNextUtf8CharStart(cell.value.items, offset);
            }
            // allow positioning to the right of the last character
            // so that the user can backspace (delete) the last character
            const last_char_pos = Vec2{ line_x - half_w, line_y };
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

    fn getPosForOffset(self: *UI, containing_cell: CellPos, target_offset: usize) Vec2 {
        const padding = self.units.paddingLeft();
        const cell = self.getCellFromIndex(containing_cell.cell_index) orelse {
            return Vec2{ containing_cell.pos[0] + padding, containing_cell.pos[1] };
        };
        var line: usize = 0;
        var col_chars: usize = 0;
        var offset: usize = 0;
        while (offset < cell.value.items.len and offset < target_offset) {
            if (cell.value.items[offset] == '\n') {
                line += 1;
                col_chars = 0;
                offset += 1;
            } else {
                col_chars += 1;
                offset = findNextUtf8CharStart(cell.value.items, offset);
            }
        }
        return Vec2{
            containing_cell.pos[0] + padding + @as(f32, @floatFromInt(col_chars)) * self.units.text.width,
            containing_cell.pos[1] + @as(f32, @floatFromInt(line)) * self.units.cell.height,
        };
    }

    fn getTextOffsetAtPoint(self: *UI, p: Vec2, containing_cell: CellPos) usize {
        const cell = self.getCellFromIndex(containing_cell.cell_index) orelse return 0;
        const text = cell.value.items;
        if (text.len == 0) return 0;

        const total_lines = countLines(cell);
        const target_line: usize = if (p[1] <= containing_cell.pos[1])
            0
        else blk: {
            const rel_y = p[1] - containing_cell.pos[1];
            const line_idx: usize = @intFromFloat(@floor(rel_y / self.units.cell.height));
            break :blk @min(line_idx, total_lines - 1);
        };

        var current_line: usize = 0;
        var offset: usize = 0;
        while (offset < text.len and current_line < target_line) {
            if (text[offset] == '\n') {
                current_line += 1;
            }
            offset += 1;
        }
        const line_start = offset;
        var line_end = line_start;
        while (line_end < text.len and text[line_end] != '\n') {
            line_end += 1;
        }

        const padding = self.units.paddingLeft();
        var line_x = containing_cell.pos[0] + padding;
        var char_offset = line_start;
        while (char_offset < line_end) {
            if (p[0] < line_x + self.units.text.width * 0.5) {
                return char_offset;
            }
            line_x += self.units.text.width;
            char_offset = findNextUtf8CharStart(text, char_offset);
        }

        return line_end;
    }

    fn getTextOffsetRangeAtPoint(self: *UI, p: Vec2, containing_cell: CellPos) OffsetRange {
        const cell = self.getCellFromIndex(containing_cell.cell_index) orelse return .{ .start = 0, .end = 0 };
        const text = cell.value.items;
        if (text.len == 0) return .{ .start = 0, .end = 0 };

        const total_lines = countLines(cell);
        const target_line: usize = if (p[1] <= containing_cell.pos[1])
            0
        else blk: {
            const rel_y = p[1] - containing_cell.pos[1];
            const line_idx: usize = @intFromFloat(@floor(rel_y / self.units.cell.height));
            break :blk @min(line_idx, total_lines - 1);
        };

        var current_line: usize = 0;
        var offset: usize = 0;
        while (offset < text.len and current_line < target_line) {
            if (text[offset] == '\n') {
                current_line += 1;
            }
            offset += 1;
        }
        const line_start = offset;
        var line_end = line_start;
        while (line_end < text.len and text[line_end] != '\n') {
            line_end += 1;
        }

        const padding = self.units.paddingLeft();
        var line_x = containing_cell.pos[0] + padding;
        if (p[0] < line_x) {
            return .{ .start = line_start, .end = line_start };
        }

        var char_offset = line_start;
        while (char_offset < line_end) {
            const next_offset = findNextUtf8CharStart(text, char_offset);
            if (p[0] >= line_x and p[0] < line_x + self.units.text.width) {
                return .{ .start = char_offset, .end = next_offset };
            }
            line_x += self.units.text.width;
            char_offset = next_offset;
        }

        return .{ .start = line_end, .end = line_end };
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

    pub fn serializeTables(self: *UI, allocator: Allocator) ![]u8 {
        var aw: std.Io.Writer.Allocating = .init(allocator);
        defer aw.deinit();

        // Write number of tables
        try aw.writer.writeInt(usize, self.tables.items.len, .little);

        // Serialize each table
        for (self.tables.items) |table| {
            const table_data = try table.serialize(allocator);
            defer allocator.free(table_data);

            // Write table data length and then the data
            try aw.writer.writeInt(usize, table_data.len, .little);
            try aw.writer.writeAll(table_data);
        }

        return try aw.toOwnedSlice();
    }

    /// This will clear existing tables and deserialize the provided data
    pub fn deserializeTables(self: *UI, allocator: Allocator, data: []const u8) !void {
        // Clear existing tables
        for (self.tables.items) |table| {
            table.deinit(allocator);
            allocator.destroy(table);
        }
        self.tables.clearRetainingCapacity();
        self.active_cursor = null;
        self.hover_cursor = null;
        self.context_menu = null;

        var reader = std.Io.Reader.fixed(data);

        // Read number of tables
        const num_tables = try reader.takeInt(usize, .little);

        // Deserialize each table
        for (0..num_tables) |_| {
            // Read table data length
            const table_data_len = try reader.takeInt(usize, .little);

            // Read table data
            const table_data = try allocator.alloc(u8, table_data_len);
            defer allocator.free(table_data);
            try reader.readSliceAll(table_data);

            // Deserialize table and add to UI
            const table = try Table.deserialize(allocator, table_data);
            const table_ptr = try allocator.create(Table);
            table_ptr.* = table;
            try self.tables.append(allocator, table_ptr);
        }
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

fn findEndOfLine(cell: *const Cell, target_line: usize) usize {
    var line: usize = 0;
    var offset: usize = 0;

    while (offset < cell.value.items.len) {
        if (line == target_line) {
            // Look for the newline character at the end of this line
            while (offset < cell.value.items.len and cell.value.items[offset] != '\n') {
                offset += 1;
            }
            return offset; // This is the position of the newline or end of string
        }

        const char = cell.value.items[offset];
        if (char == '\n') {
            line += 1;
        }
        offset += 1;
    }

    return offset; // End of string
}

fn findPrevUtf8CharStart(utf8_text: []const u8, current_offset: usize) usize {
    if (current_offset == 0) return 0;

    var prev_char_start = current_offset;
    while (prev_char_start > 0) {
        prev_char_start -= 1;
        // Check if this is the start of a UTF-8 character (not a continuation byte)
        if (prev_char_start >= utf8_text.len or (utf8_text[prev_char_start] & 0x80) == 0 or (utf8_text[prev_char_start] & 0xC0) == 0xC0) {
            break;
        }
    }
    return prev_char_start;
}

fn findNextUtf8CharStart(utf8_text: []const u8, current_offset: usize) usize {
    if (current_offset >= utf8_text.len) return utf8_text.len;

    var next_char_start = current_offset;
    if (next_char_start < utf8_text.len) {
        // Move past the current character's bytes
        next_char_start += 1;
        // Skip continuation bytes to find the next character start
        while (next_char_start < utf8_text.len and (utf8_text[next_char_start] & 0xC0) == 0x80) {
            next_char_start += 1;
        }
    }
    return next_char_start;
}

fn isPrintableChar(char_code: u32) bool {
    // Control characters (0-31) and DEL (127) are not printable
    if (char_code < 32 or char_code == 127) {
        return false;
    }

    // Basic Latin (32-126) - printable ASCII
    if (char_code <= 126) {
        return true;
    }

    // C1 Control Characters (128-159) are not printable
    if (char_code >= 128 and char_code <= 159) {
        return false;
    }

    // Latin-1 Supplement and beyond (160+) - most Unicode characters are printable
    // This includes accented characters, symbols, emoji, etc.
    // We exclude some specific ranges that are known to be non-printable:

    // Unicode line and paragraph separators
    if (char_code == 0x2028 or char_code == 0x2029) {
        return false;
    }

    // Unicode format characters (invisible)
    if (char_code >= 0x200B and char_code <= 0x200F) { // Zero-width spaces and marks
        return false;
    }
    if (char_code >= 0x202A and char_code <= 0x202E) { // Bidirectional format characters
        return false;
    }
    if (char_code >= 0xFEFF and char_code <= 0xFEFF) { // Byte order mark
        return false;
    }

    // For most other Unicode characters, assume they are printable
    // This covers Latin extended, Cyrillic, Greek, Arabic, CJK, emoji, etc.
    return true;
}

const CharClass = enum {
    word,
    whitespace,
    punctuation,
    newline,
};

fn getCharClass(byte: u8) CharClass {
    if (byte == '\n' or byte == '\r') return .newline;
    if (byte == ' ' or byte == '\t') return .whitespace;
    if (std.ascii.isAlphanumeric(byte) or byte == '_' or byte >= 0x80) return .word;
    return .punctuation;
}

test "drag to select, double-click word to select, copy and delete" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const units = Units{
        .cell = .{ .width = 10.0, .height = 10.0 },
        .text = .{ .width = 5.0, .height = 10.0 },
    };
    var ui = UI.init(allocator, units);
    defer ui.deinit(allocator);

    const table = try ui.addTable(allocator);
    table.position = .{ .left = 0, .top = 0 };
    const col = try table.addColumn(allocator);
    try col.addCell(allocator, "Hello world");

    const padding = units.paddingLeft(); // 2.0
    // Characters start at x = 2.0, each 5.0 wide:
    // 'H': [2, 7), 'e': [7, 12), 'l': [12, 17), 'l': [17, 22), 'o': [22, 27), ' ': [27, 32),
    // 'w': [32, 37), 'o': [37, 42), 'r': [42, 47), 'l': [47, 52), 'd': [52, 57)

    // 1. Double-click on "Hello" (at 'e', x = 9.0, y = 5.0)
    ui.handleMouseDoubleClick(Vec2{ padding + 7.0, 5.0 });
    try testing.expect(ui.active_cursor != null);
    try testing.expect(ui.active_cursor.? == .text_selection);
    try testing.expectEqual(@as(usize, 0), ui.active_cursor.?.text_selection.start_offset);
    try testing.expectEqual(@as(usize, 5), ui.active_cursor.?.text_selection.end_offset);

    const copied1 = try ui.handleCopy(allocator);
    defer allocator.free(copied1);
    try testing.expectEqualStrings("Hello", copied1);

    // 2. Double-click on "world" (at 'r', x = 2 + 8*5 + 1 = 43.0, y = 5.0)
    ui.handleMouseDoubleClick(Vec2{ padding + 41.0, 5.0 });
    try testing.expect(ui.active_cursor != null);
    try testing.expect(ui.active_cursor.? == .text_selection);
    try testing.expectEqual(@as(usize, 6), ui.active_cursor.?.text_selection.start_offset);
    try testing.expectEqual(@as(usize, 11), ui.active_cursor.?.text_selection.end_offset);

    const copied2 = try ui.handleCopy(allocator);
    defer allocator.free(copied2);
    try testing.expectEqualStrings("world", copied2);

    // 3. Drag to select left-to-right across "llo w" (char 2..7: boundary 2 at padding+10 to boundary 7 at padding+35)
    ui.handleMouseDrag(Vec2{ padding + 11.0, 5.0 }, Vec2{ padding + 34.0, 5.0 });
    try testing.expect(ui.active_cursor != null);
    try testing.expect(ui.active_cursor.? == .text_selection);
    try testing.expectEqual(@as(usize, 2), ui.active_cursor.?.text_selection.start_offset);
    try testing.expectEqual(@as(usize, 7), ui.active_cursor.?.text_selection.end_offset);

    const copied3 = try ui.handleCopy(allocator);
    defer allocator.free(copied3);
    try testing.expectEqualStrings("llo w", copied3);

    // 4. Drag to select right-to-left across "llo w"
    ui.handleMouseDrag(Vec2{ padding + 34.0, 5.0 }, Vec2{ padding + 11.0, 5.0 });
    try testing.expect(ui.active_cursor != null);
    try testing.expect(ui.active_cursor.? == .text_selection);
    try testing.expectEqual(@as(usize, 2), ui.active_cursor.?.text_selection.start_offset);
    try testing.expectEqual(@as(usize, 7), ui.active_cursor.?.text_selection.end_offset);

    // 5. Delete the selection with BACKSPACE
    ui.handleKeyDown(allocator, .BACKSPACE, 0);
    try testing.expectEqualStrings("Heorld", col.data.items[0].value.items);
    try testing.expect(ui.active_cursor != null);
    try testing.expect(ui.active_cursor.? == .text);
    try testing.expectEqual(@as(usize, 2), ui.active_cursor.?.text.char_offset);

    // 6. Click on left half vs right half of a character snaps between characters
    // 'H' is at [padding + 0, padding + 5). Left half (< padding + 2.5) -> offset 0; right half (>= padding + 2.5) -> offset 1.
    ui.handleMouseClick(allocator, Vec2{ padding + 1.0, 5.0 });
    try testing.expectEqual(@as(usize, 0), ui.active_cursor.?.text.char_offset);
    ui.handleMouseClick(allocator, Vec2{ padding + 4.0, 5.0 });
    try testing.expectEqual(@as(usize, 1), ui.active_cursor.?.text.char_offset);

    const cursor_rect = ui.active_cursor.?.getRect(&ui, theme.current().active_cursor_color);
    try testing.expect(cursor_rect.width < units.text.width);
    try testing.expectApproxEqAbs(padding + 5.0, cursor_rect.x + cursor_rect.width * 0.5, 1e-4);
}

test "context menu delete row, column, and table" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const units = Units{
        .cell = .{ .width = 10.0, .height = 10.0 },
        .text = .{ .width = 5.0, .height = 10.0 },
    };
    var ui = UI.init(allocator, units);
    defer ui.deinit(allocator);

    const table = try ui.addTable(allocator);
    table.position = .{ .left = 0, .top = 0 };
    const col0 = try table.addColumn(allocator);
    const col1 = try table.addColumn(allocator);
    try col0.addCell(allocator, "A1");
    try col0.addCell(allocator, "A2");
    try col1.addCell(allocator, "B1");
    try col1.addCell(allocator, "B2");

    // Right-click on row 0, col 0 (at (5.0, 5.0))
    const click_pos = Vec2{ 5.0, 5.0 };
    ui.handleMouseRightClick(click_pos);
    try testing.expect(ui.context_menu != null);
    try testing.expectEqual(@as(usize, 0), ui.context_menu.?.cell_index.row_index);
    try testing.expectEqual(@as(usize, 0), ui.context_menu.?.cell_index.column_index);

    const item_h = ui.contextMenuItemHeight();

    // Hover and click item 0: "Delete row"
    const delete_row_pos = Vec2{ click_pos[0] + 5.0, click_pos[1] + item_h * 0.5 };
    ui.handleMouseHover(delete_row_pos);
    try testing.expectEqual(ContextMenuAction.delete_row, ui.context_menu.?.hovered_item.?);
    ui.handleMouseClick(allocator, delete_row_pos);
    try testing.expect(ui.context_menu == null);
    try testing.expectEqual(@as(usize, 1), table.rows());
    try testing.expectEqualStrings("A2", table.columns.items[0].data.items[0].value.items);
    try testing.expectEqualStrings("B2", table.columns.items[1].data.items[0].value.items);

    // Right-click on col 1, row 0 and click item 1: "Delete column"
    const col1_x = table.columns.items[0].size(units).width + 2.0;
    const col1_click = Vec2{ col1_x, 5.0 };
    ui.handleMouseRightClick(col1_click);
    try testing.expect(ui.context_menu != null);
    try testing.expectEqual(@as(usize, 1), ui.context_menu.?.cell_index.column_index);

    const delete_col_pos = Vec2{ col1_click[0] + 5.0, col1_click[1] + item_h * 1.5 };
    ui.handleMouseHover(delete_col_pos);
    try testing.expectEqual(ContextMenuAction.delete_column, ui.context_menu.?.hovered_item.?);
    ui.handleMouseClick(allocator, delete_col_pos);
    try testing.expect(ui.context_menu == null);
    try testing.expectEqual(@as(usize, 1), table.cols());
    try testing.expectEqualStrings("A2", table.columns.items[0].data.items[0].value.items);

    // Right-click on remaining cell and click item 2: "Delete table"
    ui.handleMouseRightClick(click_pos);
    try testing.expect(ui.context_menu != null);
    const delete_table_pos = Vec2{ click_pos[0] + 5.0, click_pos[1] + item_h * 2.5 };
    ui.handleMouseHover(delete_table_pos);
    try testing.expectEqual(ContextMenuAction.delete_table, ui.context_menu.?.hovered_item.?);
    ui.handleMouseClick(allocator, delete_table_pos);
    try testing.expect(ui.context_menu == null);
    try testing.expectEqual(@as(usize, 0), ui.tables.items.len);
    try testing.expect(ui.active_cursor == null);
}
