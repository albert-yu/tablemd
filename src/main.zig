const std = @import("std");
// const re = @cImport(@cInclude("regez.h"));
const re = @import("regex.zig");
const print = std.debug.print;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    // var slice = try allocator.alignedAlloc(u8, REGEX_T_ALIGNOF, REGEX_T_SIZEOF);
    // const regex = @as(*re.regex_t, @ptrCast(slice.ptr));
    // defer allocator.free(slice);
    // if (re.regcomp(regex, "hello ?([[:alpha:]]*)", re.REG_EXTENDED | re.REG_ICASE) != 0) {
    //     print("Invalid Regular Expression", .{});
    //     return;
    // }
    // defer re.regfree(regex); // IMPORTANT!!
    // const input = "hello Teg!";
    // var matches: [5]re.regmatch_t = undefined;
    // if (re.regexec(regex, input, matches.len, &matches, 0) != 0) {
    //     // TODO: no match
    // }
    const regex = try re.Regex.new(allocator, "hello ?([[:alpha:]]*)");
    defer regex.destroy(allocator);
    const input = "hello Teg!";
    const matches = try regex.eval(allocator, input);
    defer allocator.free(matches);
    for (matches, 0..) |m, i| {
        const match = input[m.start..m.end];
        print("matches[{d}] = {s}\n", .{ i, match });
    }
}

test "simple test" {}
