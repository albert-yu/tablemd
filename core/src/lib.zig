const std = @import("std");
const engine = @import("engine.zig");

const Sheet = engine.Sheet;

/// Don't use directly, use consoleLog instead
extern fn print(ptr: [*]const u8, len: u32) void;

extern fn print_u32(value: u32) void;

/// Wrapper around `print` to make it easier to use
fn consoleLog(str: []const u8) void {
    print(str.ptr, str.len);
}

/// Represents the running application
const App = struct {
    sheets: []Sheet,
    allocator: std.mem.Allocator,
    canvas_buffer: []u8,
    canvas_width: usize,
    canvas_height: usize,

    pub fn init(allocator: std.mem.Allocator, canvas_width: usize, canvas_height: usize, sheet_count: usize) !App {
        const sheets = try allocator.alloc(Sheet, sheet_count);
        errdefer allocator.free(sheets);
        const canvas_size = canvas_height * canvas_width * 4;
        const canvas_buffer = try allocator.alloc(u8, canvas_size);

        // set all pixels to white
        for (canvas_buffer, 0..) |_, i| {
            canvas_buffer[i] = 255;
        }

        return App{
            .canvas_width = canvas_width,
            .canvas_height = canvas_height,
            .sheets = sheets,
            .allocator = allocator,
            .canvas_buffer = canvas_buffer,
        };
    }

    pub fn deinit(self: App) void {
        self.allocator.free(self.sheets);
        self.allocator.free(self.canvas_buffer);
    }

    pub fn getAllocator(self: App) std.mem.Allocator {
        return self.allocator;
    }

    pub fn getCanvasElementAt(self: App, index: usize) u8 {
        return self.canvas_buffer[index];
    }

    pub fn getCanvasBuffer(self: *App) []u8 {
        return self.canvas_buffer;
    }

    pub fn drawGrid(self: *App) void {
        const canvas_width = self.canvas_width;
        const canvas_height = self.canvas_height;
        // gray
        const grid_color = 0x000000ff;
        const cell_height = 10;
        const cell_width = cell_height * 2;

        const size = canvas_width * canvas_height;
        for (0..size) |i| {
            const x = i % canvas_width;
            const y = i / canvas_width;
            const x_mod_w = x % cell_width;
            const y_mod_h = y % cell_height;
            const draw_x = x_mod_w == 0 or x_mod_w == 1;
            const draw_y = y_mod_h == 0 or y_mod_h == 1;
            if (draw_x or draw_y) {
                self.set(x, y, grid_color);
            }
        }
    }

    fn setIdx(self: *App, idx: usize, v: u32) void {
        // wasm is little-endian
        const b1: u8 = @truncate(v & 0xff);
        const b2: u8 = @truncate((v >> 8) & 0xff);
        const b3: u8 = @truncate((v >> 16) & 0xff);
        const b4: u8 = @truncate((v >> 24) & 0xff);
        self.canvas_buffer[idx] = b1;
        self.canvas_buffer[idx + 1] = b2;
        self.canvas_buffer[idx + 2] = b3;
        self.canvas_buffer[idx + 3] = b4;
    }

    fn set(self: *App, x: u32, y: u32, v: u32) void {
        const store_size = 4; // 32 / 8
        const idx = (y * self.canvas_width + x) * store_size;
        self.setIdx(idx, v);
    }
};

/// Returns null if failed to allocate
export fn app_init(canvas_width: usize, canvas_height: usize, sheet_count: usize) ?*App {
    const allocator = std.heap.wasm_allocator;
    const app = App.init(allocator, canvas_width, canvas_height, sheet_count) catch {
        return null;
    };
    const allocated_app = allocator.create(App) catch {
        app.deinit();
        return null;
    };
    allocated_app.* = app;
    allocated_app.drawGrid();
    return allocated_app;
}

export fn app_deinit(app: *App) void {
    const allocator = app.getAllocator();
    app.deinit();
    allocator.destroy(app);
    consoleLog("App freed");
}

export fn get_canvas_buffer_ptr(app: *App) [*]u8 {
    return app.getCanvasBuffer().ptr;
}
