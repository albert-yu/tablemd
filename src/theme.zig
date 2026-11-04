const sokol = @import("sokol");
const sg = sokol.gfx;

pub const Theme = struct {
    background_color: sg.Color,
    text_color: sg.Color,
    active_cursor_color: sg.Color,
    hover_cursor_color: sg.Color,
    table_background_color: sg.Color,
    dot_grid_color: sg.Color,
};

pub const DARK_THEME: Theme = .{
    .background_color = .{
        .r = 14.0 / 256.0,
        .g = 33.0 / 256.0,
        .b = 47.0 / 256.0,
        .a = 1.0,
    },
    .text_color = .{
        .r = 1.0,
        .g = 1.0,
        .b = 1.0,
        .a = 1.0,
    },
    .active_cursor_color = .{
        .r = 0.5,
        .g = 0.8,
        .b = 1.0,
        .a = 0.8,
    },
    .hover_cursor_color = .{
        .r = 0.7,
        .g = 0.9,
        .b = 1.0,
        .a = 0.4,
    },
    .table_background_color = .{
        .r = 0.0,
        .g = 214.0 / 256.0,
        .b = 196.0 / 256.0,
        .a = 0.50,
    },
    .dot_grid_color = .{
        .r = 1.0,
        .g = 1.0,
        .b = 1.0,
        .a = 0.25,
    },
};

pub const LIGHT_THEME: Theme = .{
    .background_color = .{
        .r = 244.0 / 255.0,
        .g = 247.0 / 255.0,
        .b = 248.0 / 255.0,
        .a = 1.0,
    },
    .text_color = .{
        .r = 23.0 / 255.0,
        .g = 48.0 / 255.0,
        .b = 66.0 / 255.0,
        .a = 1.0,
    },
    .active_cursor_color = .{
        .r = 0.0,
        .g = 112.0 / 255.0,
        .b = 138.0 / 255.0,
        .a = 0.55,
    },
    .hover_cursor_color = .{
        .r = 0.0,
        .g = 112.0 / 255.0,
        .b = 138.0 / 255.0,
        .a = 0.22,
    },
    .table_background_color = .{
        .r = 30.0 / 255.0,
        .g = 174.0 / 255.0,
        .b = 164.0 / 255.0,
        .a = 0.22,
    },
    .dot_grid_color = .{
        .r = 23.0 / 255.0,
        .g = 48.0 / 255.0,
        .b = 66.0 / 255.0,
        .a = 0.22,
    },
};

var dark_mode = true;
var current_theme = DARK_THEME;

pub fn current() Theme {
    return current_theme;
}

pub fn isDarkMode() bool {
    return dark_mode;
}

pub fn setDarkMode(is_dark: bool) void {
    dark_mode = is_dark;
    current_theme = if (is_dark) DARK_THEME else LIGHT_THEME;
}
