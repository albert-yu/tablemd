const std = @import("std");
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const rect = @import("rect.zig");
const line = @import("line.zig");
const font = @import("font.zig");

const RectElement = rect.RectElement;
const LineElement = line.LineElement;
const TextElement = font.TextElement;

pub const Scene = struct {
    rects: ArrayList(RectElement),
    lines: ArrayList(LineElement),
    texts: ArrayList(TextElement),

    pub fn init(allocator: Allocator) Scene {
        return Scene{
            .rects = ArrayList(RectElement).initCapacity(allocator, 0) catch unreachable,
            .lines = ArrayList(LineElement).initCapacity(allocator, 0) catch unreachable,
            .texts = ArrayList(TextElement).initCapacity(allocator, 0) catch unreachable,
        };
    }

    pub fn deinit(self: *Scene, allocator: Allocator) void {
        self.rects.deinit(allocator);
        self.lines.deinit(allocator);
        self.texts.deinit(allocator);
    }

    pub fn clear(self: *Scene) void {
        self.rects.clearRetainingCapacity();
        self.lines.clearRetainingCapacity();
        self.texts.clearRetainingCapacity();
    }
};
