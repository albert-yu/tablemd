const std = @import("std");
const engine = @import("engine.zig");

const Sheet = engine.Sheet;

/// Don't use directly, use consoleLog instead
extern fn print(ptr: [*]const u8, len: u32) void;

extern fn print_u32(value: u32) void;

var width: u32 = 0;
var height: u32 = 0;
var offset: u32 = 0;

/// Wrapper around `print` to make it easier to use
fn consoleLog(str: []const u8) void {
    print(str.ptr, str.len);
}

/// Represents the running application
const App = struct {
    sheets: []Sheet,
    allocator: std.mem.Allocator,
    canvas_buffer: []u8,
    pub fn init(allocator: std.mem.Allocator, canvas_width: usize, canvas_height: usize, sheet_count: usize) !App {
        const sheets = try allocator.alloc(Sheet, sheet_count);
        errdefer allocator.free(sheets);
        const canvas_size = canvas_height * canvas_width;
        const canvas_buffer = try allocator.alloc(u8, canvas_size);
        return App{
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

    fn set(self: *App, x: u32, y: u32, v: u32) void {
        const store_size = 4; // 32 / 8
        const idx = (offset + y * width + x) * store_size;
        print_u32(idx);
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
};

/// Returns null if failed to allocate
export fn app_init(canvas_width: usize, canvas_height: usize, sheet_count: usize) ?*App {
    const allocator = std.heap.wasm_allocator;
    const app = App.init(allocator, canvas_height, canvas_width, sheet_count) catch {
        return null;
    };
    const allocated_app = allocator.create(App) catch {
        app.deinit();
        return null;
    };
    allocated_app.* = app;
    return allocated_app;
}

export fn app_deinit(app: *App) void {
    const allocator = app.getAllocator();
    app.deinit();
    allocator.destroy(app);
    consoleLog("App freed");
}
