const std = @import("std");
const ArrayList = std.ArrayListUnmanaged;
const Allocator = std.mem.Allocator;
const rect = @import("rect.zig");
const text = @import("text.zig");

const RectElement = rect.RectElement;
const TextElement = text.TextElement;

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