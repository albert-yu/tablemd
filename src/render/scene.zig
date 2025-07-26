const std = @import("std");
const ArrayList = std.ArrayListUnmanaged;
const Allocator = std.mem.Allocator;
const sokol = @import("sokol");
const rect = @import("rect.zig");
const text = @import("text.zig");

const sg = sokol.gfx;

const RectElement = rect.RectElement;
const TextElement = text.TextElement;

pub const Scene = struct {
    rects: ArrayList(RectElement),
    texts: ArrayList(TextElement),
    // Store allocated text strings so they can be freed when scene is cleared
    text_strings: ArrayList([]u8),

    pub fn init(allocator: Allocator) Scene {
        return Scene{
            .rects = ArrayList(RectElement).initCapacity(allocator, 0) catch unreachable,
            .texts = ArrayList(TextElement).initCapacity(allocator, 0) catch unreachable,
            .text_strings = ArrayList([]u8).initCapacity(allocator, 0) catch unreachable,
        };
    }

    pub fn deinit(self: *Scene, allocator: Allocator) void {
        self.clearTextStrings(allocator);
        self.rects.deinit(allocator);
        self.texts.deinit(allocator);
        self.text_strings.deinit(allocator);
    }

    pub fn clear(self: *Scene, allocator: Allocator) void {
        self.clearTextStrings(allocator);
        self.rects.clearRetainingCapacity();
        self.texts.clearRetainingCapacity();
        self.text_strings.clearRetainingCapacity();
    }

    fn clearTextStrings(self: *Scene, allocator: Allocator) void {
        for (self.text_strings.items) |text_string| {
            allocator.free(text_string);
        }
    }

    pub fn addText(self: *Scene, allocator: Allocator, text_string: []u8, x: f32, y: f32, color: sg.Color) !void {
        // Store the text string so it can be freed later
        try self.text_strings.append(allocator, text_string);
        try self.texts.append(allocator, .{
            .text = text_string,
            .x = x,
            .y = y,
            .color = color,
        });
    }
};
