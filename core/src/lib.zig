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

const CellPosition = struct {
    row: u32,
    col: u32,
};

fn setDword(buffer: []u8, idx: usize, dword: u32) void {
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
    canvas_width: usize,
    canvas_height: usize,
    current_cell: ?CellPosition,

    pub fn init(allocator: std.mem.Allocator, canvas_width: usize, canvas_height: usize, sheet_count: usize) !App {
        const sheets = try allocator.alloc(Sheet, sheet_count);
        errdefer allocator.free(sheets);

        return App{
            .canvas_width = canvas_width,
            .canvas_height = canvas_height,
            .sheets = sheets,
            .allocator = allocator,
            .current_cell = null,
        };
    }

    pub fn deinit(self: App) void {
        self.allocator.free(self.sheets);
    }

    pub fn getAllocator(self: App) std.mem.Allocator {
        return self.allocator;
    }

    pub fn setCanvasSize(self: *App, width: usize, height: usize) void {
        self.canvas_width = width;
        self.canvas_height = height;
    }

    fn updateCurrentCell(self: *App, cell: ?CellPosition) void {
        self.current_cell = cell;
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
    consoleLog("App initialized");
    return allocated_app;
}

export fn app_deinit(app: *App) void {
    const allocator = app.getAllocator();
    app.deinit();
    allocator.destroy(app);
    consoleLog("App freed");
}

export fn app_set_canvas_size(app: *App, width: usize, height: usize) void {
    app.setCanvasSize(width, height);
}
