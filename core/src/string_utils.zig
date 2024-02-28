const std = @import("std");

pub fn copyString(allocator: std.mem.Allocator, s: []const u8) ![]const u8 {
    const len = s.len;
    const str = try allocator.alloc(u8, len);
    @memcpy(str, s);
    return str;
}
