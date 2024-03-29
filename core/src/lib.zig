const std = @import("std");
const engine = @import("engine.zig");

extern fn print_char(c: u8) void;

/// Couples engine.Sheet with std.heap.page_allocator
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
    const allocator = std.heap.page_allocator;
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

fn printString(s: []const u8) void {
    for (s) |c| {
        print_char(c);
    }
    print_char(0);
}

export fn freeSheet(sheet: *Sheet) void {
    const allocator = sheet.allocator;
    sheet.deinit();
    allocator.destroy(sheet);
    const s = "freed";
    printString(s);
}
