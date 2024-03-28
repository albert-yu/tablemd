const std = @import("std");
const engine = @import("engine.zig");

/// Couples engine.Sheet with std.heap.page_allocator
const Sheet = struct {
    inner: engine.Sheet,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) !Sheet {
        const inner = try engine.Sheet.new(allocator);
        return Sheet{
            .inner = inner,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Sheet) void {
        self.inner.deinit(self.allocator);
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

export fn freeSheet(sheet: *Sheet) void {
    const allocator = sheet.allocator;
    sheet.deinit();
    allocator.destroy(sheet);
}
