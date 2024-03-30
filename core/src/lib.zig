const std = @import("std");
const engine = @import("engine.zig");

/// Don't use directly, use consoleLog instead
extern fn print(ptr: [*]const u8, len: u32) void;

/// Exported memory
extern var memory: [*]u8;

var width: u32 = 0;
var height: u32 = 0;
var offset: u32 = 0;

fn set(x: u32, y: u32, v: u32) void {
    const store_size = 4; // 32 / 8
    const idx = (offset + y * width + x) * store_size;
    // wasm is little-endian
    const b1: u8 = @truncate(v & 0xff);
    const b2: u8 = @truncate((v >> 8) & 0xff);
    const b3: u8 = @truncate((v >> 16) & 0xff);
    const b4: u8 = @truncate((v >> 24) & 0xff);
    memory[idx] = b1;
    memory[idx + 1] = b2;
    memory[idx + 2] = b3;
    memory[idx + 3] = b4;
}

export fn init(w: u32, h: u32) void {
    width = w;
    height = h;
    offset = w * h;

    // fill memory with black pixels
    for (0..h) |y| {
        for (0..w) |x| {
            set(x, y, 0);
        }
    }
}

/// Wrapper around `print` to make it easier to use
fn consoleLog(str: []const u8) void {
    print(str.ptr, str.len);
}

/// Couples engine.Sheet with std.heap.wasm_allocator
const Sheet = struct {
    inner: *engine.Sheet,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) !Sheet {
        const inner = try engine.Sheet.new(allocator);
        const inner_ptr = try allocator.create(engine.Sheet);
        inner_ptr.* = inner;
        return Sheet{
            .inner = inner_ptr,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: Sheet) void {
        self.inner.deinit(self.allocator);
        self.allocator.destroy(self.inner);
    }

    pub fn eval(self: *Sheet, source: []const u8) ?engine.Result {
        const result = self.inner.eval(self.allocator, source) catch {
            return null;
        };
        return result;
    }
};

export fn newSheet() ?*Sheet {
    const allocator = std.heap.wasm_allocator;
    const sheet = Sheet.init(allocator) catch {
        return null;
    };
    const allocated_sheet = allocator.create(Sheet) catch {
        sheet.deinit();
        return null;
    };
    allocated_sheet.* = sheet;
    return allocated_sheet;
}

export fn freeSheet(sheet: *Sheet) void {
    const allocator = sheet.allocator;
    sheet.deinit();
    allocator.destroy(sheet);
    consoleLog("Sheet freed");
}
