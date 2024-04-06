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

fn setDword(buffer: []u8, idx: usize, dword: u32) void {
    // wasm is little-endian
    const alpha: u8 = @truncate(dword & 0xff);
    const blue: u8 = @truncate((dword >> 8) & 0xff);
    const green: u8 = @truncate((dword >> 16) & 0xff);
    const red: u8 = @truncate((dword >> 24) & 0xff);
    buffer[idx] = red;
    buffer[idx + 1] = green;
    buffer[idx + 2] = blue;
    buffer[idx + 3] = alpha;
}

/// Represents the running application
const App = struct {
    sheets: []Sheet,
    allocator: std.mem.Allocator,
    canvas_buffer: []u8,
    canvas_width: usize,
    canvas_height: usize,
    rows: usize,
    cols: usize,

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
            .rows = 10,
            .cols = 5,
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

    pub fn getCanvasBuffer(self: *App) []u8 {
        return self.canvas_buffer;
    }

    pub fn drawGrid(self: *App) void {
        const canvas_width = self.canvas_width;
        const canvas_height = self.canvas_height;
        const grid_color = 0x000000ff;
        const cell_height = canvas_height / self.rows;
        const cell_width = canvas_width / self.cols;

        for (0..canvas_height) |y| {
            for (0..canvas_width) |x| {
                if (x % cell_width == 0 or y % cell_height == 0) {
                    self.set(x, y, grid_color);
                }
            }
        }
    }

    fn set(self: *App, x: u32, y: u32, rgba: u32) void {
        const store_size = 4; // 32 / 8
        const idx = (y * self.canvas_width + x) * store_size;
        setDword(self.canvas_buffer, idx, rgba);
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
