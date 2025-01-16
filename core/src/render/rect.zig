const std = @import("std");

const RectElement = struct {
    color: [4]f32,
    x: f32,
    y: f32,
    width: f32,
    height: f32,
    corners: [4]f32,
    sigma: f32,
};

const DEFAULT_SIGMA = 1e-6;

pub const Renderer = struct {
    hover_rect: RectElement,
    /// Currently not used
    rect_data: []f32,

    pub fn init(allocator: std.mem.Allocator) !Renderer {
        const data = try allocator.alloc(f32, 1000 * @sizeOf(RectElement));
        return Renderer{
            .hover_rect = RectElement{
                .x = 0,
                .y = 0,
                .width = 0,
                .height = 0,
                .color = [4]f32{ 0, 0, 0, 0.25 },
                .corners = [4]f32{ 0, 0, 0, 0 },
                .sigma = DEFAULT_SIGMA,
            },
            .rect_data = data,
        };
    }

    pub fn deinit(self: Renderer, allocator: std.mem.Allocator) void {
        allocator.free(self.rect_data);
    }

    fn writeRect(self: *Renderer, offset: usize, rect: RectElement) void {
        const UNUSED = 0.0;
        const float_array = self.rect_data;
        float_array[offset] = rect.color[0];
        float_array[offset + 1] = rect.color[1];
        float_array[offset + 2] = rect.color[2];
        float_array[offset + 3] = rect.color[3];
        float_array[offset + 4] = rect.x;
        float_array[offset + 5] = rect.y;
        float_array[offset + 6] = UNUSED;
        float_array[offset + 7] = rect.sigma;
        float_array[offset + 8] = rect.corners[0];
        float_array[offset + 9] = rect.corners[1];
        float_array[offset + 10] = rect.corners[2];
        float_array[offset + 11] = rect.corners[3];
        float_array[offset + 12] = rect.width;
        float_array[offset + 13] = rect.height;
        float_array[offset + 14] = UNUSED;
        float_array[offset + 15] = UNUSED;
    }
};
