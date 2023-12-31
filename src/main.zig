const std = @import("std");
const re = @cImport(@cInclude("regez.h"));
const REGEX_T_ALIGNOF = re.sizeof_regex_t;
const REGEX_T_SIZEOF = re.alignof_regex_t;
const print = std.debug.print;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var slice = try allocator.alignedAlloc(u8, REGEX_T_ALIGNOF, REGEX_T_SIZEOF);
    const regex = @as(*re.regex_t, @ptrCast(slice.ptr));
    defer allocator.free(@as([*]u8, @ptrCast(regex))[0..REGEX_T_SIZEOF]);
    if (re.regcomp(regex, "hello ?([[:alpha:]]*)", re.REG_EXTENDED | re.REG_ICASE) != 0) {
        print("Invalid Regular Expression", .{});
        return;
    }
    defer re.regfree(regex); // IMPORTANT!!
    const input = "hello Teg!";
    var matches: [5]re.regmatch_t = undefined;
    if (re.regexec(regex, input, matches.len, &matches, 0) != 0) {
        // TODO: no match
    }

    for (matches, 0..) |m, i| {
        const start_offset = m.rm_so;
        if (start_offset == -1) {
            break;
        }

        const end_offset = m.rm_eo;

        const match = input[@as(usize, @intCast(start_offset))..@as(usize, @intCast(end_offset))];
        print("matches[{d}] = {s}\n", .{ i, match });
    }
}

test "simple test" {}
