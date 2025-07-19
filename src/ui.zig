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

    pub fn deinit(self: *Scene) void {
        self.rects.deinit(self.allocator);
        self.texts.deinit(self.allocator);
    }
};

pub const Position = struct {
    left: usize,
    top: usize,
};

pub const TextPosition = struct {
    left: usize,
    top: usize,
    char_offset: usize,
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
};

pub const Table = struct {
    position: Position,
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

        return scene;
    }
};
