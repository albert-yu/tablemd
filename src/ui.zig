const std = @import("std");
const ArrayList = std.ArrayListUnmanaged;
const Allocator = std.mem.Allocator;
const grid = @import("render/dot_grid.zig");
const rect = @import("render/rect.zig");
const text = @import("render/text.zig");

const RectElement = rect.RectElement;
const TextElement = text.TextElement;
const Size2D = grid.Size2D;

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
        var curr_line_width = 0.0;
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

    pub fn addSelfToScene(self: Cell, scene: *Scene, units: Units, position: PosVec2) !void {
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
                try scene.texts.append(self.allocator, .{
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
            try scene.texts.append(self.allocator, .{
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

    pub fn size(self: *Column, units: Units) Size2D {
        var width: f32 = 0.0;
        var height: f32 = 0.0;
        for (self.data.items) |cell| {
            const cell_dims = cell.size(units);
            width = @max(width, cell_dims.width);
            height += cell_dims.height;
        }
        return .{ .width = width, .height = height };
    }

    pub fn addSelfToScene(self: Column, scene: *Scene, units: Units, position: PosVec2) !void {
        var pos_y = position.y;
        for (self.data.items) |cell| {
            const cell_dims = cell.size(units);
            try cell.addSelfToScene(scene, units, .{
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

    pub fn size(self: *Table, units: Units) Size2D {
        var width: f32 = 0.0;
        var height: f32 = 0.0;
        for (self.columns.items) |column| {
            const column_dims = column.size(units);
            width += column_dims.width;
            height += column_dims.height;
        }
        return .{ .width = width, .height = height };
    }

    pub fn addSelfToScene(self: Table, scene: *Scene, units: Units) !void {
        const cell_units = units.cell;
        const actual_position_x = self.position.left * cell_units.width;
        const actual_position_y = self.position.top * cell_units.height;
        const rect_size = self.size(units);
        const corner = 1.0 / 512.0;
        try scene.rects.append(self.allocator, .{
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
            try column.addSelfToScene(scene, units, .{
                .x = pos_x,
                .y = actual_position_y,
            });
            pos_x += col_size.width;
        }

        return scene;
    }
};

pub const CursorType = enum {
    cell,
    text,
};

pub const Cursor = union(CursorType) {
    cell: GridPos,
    text: GridPosText,
};

pub const UI = struct {
    tables: ArrayList(Table),
    active_cursor: Cursor,
};
