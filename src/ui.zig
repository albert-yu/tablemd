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

const Cell = struct {
    value: []const u8,

    pub fn size(self: Cell, units: Units) Size2D {
        const cell_units = units.cell;
        const text_units = units.text;
        var height: f32 = 0.0;
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
        const container_width = divCeil(width, cell_units.width);
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

    pub fn size(self: Table, units: Units) Size2D {
        var width: f32 = 0.0;
        var height: f32 = 0.0;
        for (self.columns.items) |column| {
            const column_dims = column.size(units);
            width += column_dims.width;
            height += column_dims.height;
        }
        return .{ .width = width, .height = height };
    }

    pub fn addSelfToScene(self: Table, scene: *Scene, allocator: Allocator, units: Units) !void {
        const cell_units = units.cell;
        const actual_position_x = @as(f32, @floatFromInt(self.position.left)) * cell_units.width;
        const actual_position_y = @as(f32, @floatFromInt(self.position.top)) * cell_units.height;
        const rect_size = self.size(units);
        const corner = 1.0 / 512.0;
        try scene.rects.append(allocator, .{
            .color = .{ 0.0, 0.0, 0.0, 1.0 },
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

    pub fn getRect(self: Cursor, units: Units) RectElement {
        const corner = 1.0 / 512.0;
        const corners = .{ corner, corner, corner, corner };
        return switch (self) {
            .cell => |cell_pos| .{
                .color = .{ 1.0, 0.0, 0.0, 1.0 },
                .x = @as(f32, @floatFromInt(cell_pos.left)) * units.cell.width,
                .y = @as(f32, @floatFromInt(cell_pos.top)) * units.cell.height,
                .width = units.cell.width,
                .height = units.cell.height,
                .corners = corners,
                .sigma = 1e-6,
            },
            .text => |text_pos| .{
                .color = .{ 1.0, 0.0, 0.0, 1.0 },
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
    units: Units,

    pub fn init(allocator: Allocator, units: Units) UI {
        return .{
            .tables = ArrayList(Table).initCapacity(allocator, 0) catch unreachable,
            .active_cursor = null,
            .units = units,
        };
    }

    pub fn deinit(self: *UI, allocator: Allocator) void {
        self.tables.deinit(allocator);
    }

    pub fn handleMouseDown(self: *UI, p: Vec2) void {
        self.active_cursor = self.getCursor(p);
    }

    pub fn getCursor(self: UI, p: Vec2) Cursor {
        const cell_pos = self.getCellPosition(p);
        // TODO: handle text cursor
        return Cursor{ .cell = cell_pos };
    }

    pub fn addSelfToScene(self: UI, allocator: Allocator, scene: *Scene) !void {
        if (self.active_cursor) |cursor| {
            try scene.rects.append(allocator, cursor.getRect(self.units));
        }
        for (self.tables.items) |table| {
            try table.addSelfToScene(scene, allocator, self.units);
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
