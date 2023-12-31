const std = @import("std");
const re = @cImport(@cInclude("regez.h"));
const REGEX_T_ALIGNOF = re.sizeof_regex_t;
const REGEX_T_SIZEOF = re.alignof_regex_t;

pub const Match = struct {
    start: usize,
    end: usize,
};

pub const Regex = struct {
    slice: []align(@alignOf(u8)) u8,
    regex: *re.regex_t,
    const Self = @This();
    pub fn new(allocator: std.mem.Allocator, expr: []const u8) !Self {
        var slice = try allocator.alignedAlloc(u8, REGEX_T_ALIGNOF, REGEX_T_SIZEOF);
        var regex = @as(*re.regex_t, @ptrCast(slice.ptr));
        var err = re.regcomp(regex, expr.ptr, re.REG_EXTENDED | re.REG_ICASE);
        if (err != 0) {
            allocator.free(slice);
            // TODO: get actual error
            return error.InvalidRegEx;
        }
        return Self{
            .slice = slice,
            .regex = regex,
        };
    }

    pub fn destroy(self: Self, allocator: std.mem.Allocator) void {
        re.regfree(self.regex);
        allocator.free(self.slice);
    }

    /// caller must free returned slice
    pub fn eval(self: Self, allocator: std.mem.Allocator, input: []const u8) ![]Match {
        var matches_list = std.ArrayList(Match).init(allocator);
        const WINDOW_SIZE = 5;
        var matches: [WINDOW_SIZE]re.regmatch_t = undefined;

        var code = re.regexec(self.regex, input.ptr, matches.len, &matches, 0);
        var has_matches = code == 0;
        var last_end_offset: usize = 0;
        while (has_matches) {
            for (matches) |m| {
                const start_offset = m.rm_so;
                if (start_offset == -1) {
                    has_matches = false;
                    break;
                }

                const end_offset = m.rm_eo;
                const end = @as(usize, @intCast(end_offset));
                last_end_offset = end;

                const match = Match{
                    .start = @as(usize, @intCast(start_offset)),
                    .end = end,
                };
                try matches_list.append(match);
            }
            if (last_end_offset > 0) {
                // reset, start searching from end of last match
                const new_input = input[last_end_offset..];
                matches = undefined;
                var exec_result_code = re.regexec(self.regex, new_input.ptr, matches.len, &matches, 0);
                if (exec_result_code != 0) {
                    break;
                }
            } else {
                break;
            }
        }
        var as_slice = matches_list.toOwnedSlice();
        return as_slice;
    }
};
