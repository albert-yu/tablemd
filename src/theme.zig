const sokol = @import("sokol");
const sg = sokol.gfx;

pub const Theme = struct {
    background_color: sg.Color,
    text_color: sg.Color,
    active_cursor_color: sg.Color,
    hover_cursor_color: sg.Color,
    table_background_color: sg.Color,
    dot_grid_color: sg.Color,
    edited_cell_border_color: sg.Color,
};

pub const DARK_THEME: Theme = .{
    .background_color = .{
        .r = 24.0 / 255.0,
        .g = 24.0 / 255.0,
        .b = 24.0 / 255.0,
        .a = 1.0,
    },
    .text_color = .{
        .r = 1.0,
        .g = 1.0,
        .b = 1.0,
        .a = 1.0,
    },
    .active_cursor_color = .{
        .r = 1.0,
        .g = 1.0,
        .b = 1.0,
        .a = 0.28,
    },
    .hover_cursor_color = .{
        .r = 1.0,
        .g = 1.0,
        .b = 1.0,
        .a = 0.10,
    },
    .table_background_color = .{
        .r = 45.0 / 255.0,
        .g = 45.0 / 255.0,
        .b = 45.0 / 255.0,
        .a = 0.85,
    },
    .dot_grid_color = .{
        .r = 1.0,
        .g = 1.0,
        .b = 1.0,
        .a = 0.20,
    },
    .edited_cell_border_color = .{
        .r = 96.0 / 255.0,
        .g = 165.0 / 255.0,
        .b = 250.0 / 255.0,
        .a = 1.0,
    },
};

pub const LIGHT_THEME: Theme = .{
    .background_color = .{
        .r = 245.0 / 255.0,
        .g = 245.0 / 255.0,
        .b = 245.0 / 255.0,
        .a = 1.0,
    },
    .text_color = .{
        .r = 26.0 / 255.0,
        .g = 26.0 / 255.0,
        .b = 26.0 / 255.0,
        .a = 1.0,
    },
    .active_cursor_color = .{
        .r = 0.0,
        .g = 0.0,
        .b = 0.0,
        .a = 0.16,
    },
    .hover_cursor_color = .{
        .r = 0.0,
        .g = 0.0,
        .b = 0.0,
        .a = 0.07,
    },
    .table_background_color = .{
        .r = 1.0,
        .g = 1.0,
        .b = 1.0,
        .a = 0.95,
    },
    .dot_grid_color = .{
        .r = 0.0,
        .g = 0.0,
        .b = 0.0,
        .a = 0.16,
    },
    .edited_cell_border_color = .{
        .r = 37.0 / 255.0,
        .g = 99.0 / 255.0,
        .b = 235.0 / 255.0,
        .a = 1.0,
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
