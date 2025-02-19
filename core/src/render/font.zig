const std = @import("std");
const sokol = @import("sokol");
const msdf = @import("fonts/space-mono-regular/msdf.zig");
const MsdfChar = msdf.Char;

const sg = sokol.gfx;

pub const MsdfFont = struct {
    pip: sg.Pipeline,
    bind: sg.Bindings,
    line_height: f32,
    chars: std.AutoHashMap(u32, MsdfChar),
    char_count: usize,
    default_char: MsdfChar,

    pub fn init(
        allocator: std.mem.Allocator,
        pipeline: sg.Pipeline,
        bind: sg.Bindings,
        line_height: f32,
        chars: std.AutoHashMap(u32, MsdfChar),
    ) !MsdfFont {
        var char_values = std.ArrayList(MsdfChar).init(allocator);
        defer char_values.deinit();

        var chars_iterator = chars.valueIterator();
        while (chars_iterator.next()) |char| {
            try char_values.append(char.*);
        }

        return MsdfFont{
            .pip = pipeline,
            .bind = bind,
            .line_height = line_height,
            .chars = chars,
            .char_count = char_values.items.len,
            .default_char = char_values.items[0],
        };
    }

    pub fn deinit(self: *MsdfFont) void {
        self.chars.deinit();
        var kerning_iterator = self.kernings.valueIterator();
        while (kerning_iterator.next()) |kerning_map| {
            kerning_map.deinit();
        }
        self.kernings.deinit();
    }

    pub fn getChar(self: *const MsdfFont, char_code: u32) MsdfChar {
        return self.chars.get(char_code) orelse self.default_char;
    }

    pub fn getXAdvance(self: *const MsdfFont, char_code: u32) f32 {
        const char = self.getChar(char_code);
        return char.xadvance;
    }
};
