const std = @import("std");

// FreeType C bindings
pub const c = @cImport({
    @cInclude("ft2build.h");
    @cInclude("freetype/freetype.h");
    @cInclude("freetype/ftglyph.h");
    @cInclude("freetype/ftbitmap.h");
});

pub const FreeTypeError = error{
    InitError,
    LoadFaceError,
    SetSizeError,
    LoadGlyphError,
    RenderGlyphError,
    GetGlyphError,
    OutOfMemory,
};

/// FreeType library handle
pub const Library = struct {
    lib: c.FT_Library,

    pub fn init() FreeTypeError!Library {
        var lib: c.FT_Library = undefined;
        if (c.FT_Init_FreeType(&lib) != 0) {
            return FreeTypeError.InitError;
        }
        return Library{ .lib = lib };
    }

    pub fn deinit(self: Library) void {
        _ = c.FT_Done_FreeType(self.lib);
    }

    pub fn newFace(self: Library, font_data: []const u8) FreeTypeError!Face {
        var face: c.FT_Face = undefined;
        const err = c.FT_New_Memory_Face(
            self.lib,
            font_data.ptr,
            @intCast(font_data.len),
            0, // face index
            &face,
        );
        if (err != 0) {
            return FreeTypeError.LoadFaceError;
        }
        return Face{ .face = face };
    }
};

/// FreeType face handle
pub const Face = struct {
    face: c.FT_Face,

    pub fn deinit(self: Face) void {
        _ = c.FT_Done_Face(self.face);
    }

    pub fn setPixelSizes(self: Face, width: u32, height: u32) FreeTypeError!void {
        if (c.FT_Set_Pixel_Sizes(self.face, width, height) != 0) {
            return FreeTypeError.SetSizeError;
        }
    }

    pub fn loadChar(self: Face, char_code: u32, load_flags: i32) FreeTypeError!void {
        if (c.FT_Load_Char(self.face, char_code, load_flags) != 0) {
            return FreeTypeError.LoadGlyphError;
        }
    }

    pub fn renderGlyph(self: Face, render_mode: c.FT_Render_Mode) FreeTypeError!void {
        if (c.FT_Render_Glyph(self.face.*.glyph, render_mode) != 0) {
            return FreeTypeError.RenderGlyphError;
        }
    }

    pub fn getGlyphIndex(self: Face, char_code: u32) u32 {
        return c.FT_Get_Char_Index(self.face, char_code);
    }

    /// Returns glyph bitmap data
    pub fn getGlyphBitmap(self: Face) ?GlyphBitmap {
        const glyph = self.face.*.glyph;
        if (glyph == null) return null;

        const bitmap = &glyph.*.bitmap;
        if (bitmap.buffer == null) return null;

        return GlyphBitmap{
            .buffer = bitmap.buffer[0..@intCast(@as(u32, bitmap.rows) * @as(u32, @intCast(bitmap.pitch)))],
            .width = @intCast(bitmap.width),
            .height = @intCast(bitmap.rows),
            .pitch = @intCast(bitmap.pitch),
            .left = glyph.*.bitmap_left,
            .top = glyph.*.bitmap_top,
            .advance_x = @intCast(glyph.*.advance.x),
            .advance_y = @intCast(glyph.*.advance.y),
        };
    }

    /// Returns glyph metrics
    pub fn getGlyphMetrics(self: Face) ?GlyphMetrics {
        const glyph = self.face.*.glyph;
        if (glyph == null) return null;

        const metrics = &glyph.*.metrics;
        return GlyphMetrics{
            .width = @intCast(metrics.width),
            .height = @intCast(metrics.height),
            .hori_bearing_x = @intCast(metrics.horiBearingX),
            .hori_bearing_y = @intCast(metrics.horiBearingY),
            .hori_advance = @intCast(metrics.horiAdvance),
            .vert_bearing_x = @intCast(metrics.vertBearingX),
            .vert_bearing_y = @intCast(metrics.vertBearingY),
            .vert_advance = @intCast(metrics.vertAdvance),
        };
    }
};

/// Glyph bitmap information
pub const GlyphBitmap = struct {
    buffer: []u8,
    width: u32,
    height: u32,
    pitch: u32,
    left: i32,
    top: i32,
    advance_x: i32,
    advance_y: i32,
};

/// Glyph metrics information
pub const GlyphMetrics = struct {
    width: i32,
    height: i32,
    hori_bearing_x: i32,
    hori_bearing_y: i32,
    hori_advance: i32,
    vert_bearing_x: i32,
    vert_bearing_y: i32,
    vert_advance: i32,
};

/// High-level font wrapper compatible with TrueType interface
pub const Font = struct {
    library: Library,
    face: Face,

    pub fn init(font_data: []const u8) FreeTypeError!Font {
        const library = try Library.init();
        errdefer library.deinit();

        const face = try library.newFace(font_data);
        errdefer face.deinit();

        return Font{
            .library = library,
            .face = face,
        };
    }

    pub fn deinit(self: Font) void {
        self.face.deinit();
        self.library.deinit();
    }

    /// Set font size in pixels (compatible with TrueType's scaleForPixelHeight)
    pub fn setPixelHeight(self: Font, pixel_height: f32) FreeTypeError!void {
        try self.face.setPixelSizes(0, @intFromFloat(pixel_height));
    }

    /// Get glyph index for a Unicode codepoint
    pub fn codepointGlyphIndex(self: Font, codepoint: u32) ?u32 {
        const index = self.face.getGlyphIndex(codepoint);
        if (index == 0) return null;
        return index;
    }

    /// Render glyph bitmap (similar to TrueType's glyphBitmap)
    pub fn glyphBitmap(
        self: Font,
        allocator: std.mem.Allocator,
        buffer: *std.ArrayListUnmanaged(u8),
        glyph_index: u32,
        _: f32, // scale_x - not used in FreeType, size is set via setPixelHeight
        _: f32, // scale_y - not used in FreeType, size is set via setPixelHeight
    ) FreeTypeError!GlyphDimensions {
        // Load the glyph
        if (c.FT_Load_Glyph(self.face.face, glyph_index, c.FT_LOAD_DEFAULT) != 0) {
            return FreeTypeError.LoadGlyphError;
        }

        // Render the glyph to a bitmap
        try self.face.renderGlyph(c.FT_RENDER_MODE_NORMAL);

        const glyph_bitmap = self.face.getGlyphBitmap() orelse {
            return FreeTypeError.GetGlyphError;
        };

        // Copy bitmap data to buffer
        try buffer.ensureTotalCapacity(allocator, glyph_bitmap.buffer.len);
        buffer.clearRetainingCapacity();
        try buffer.appendSlice(allocator, glyph_bitmap.buffer);

        return GlyphDimensions{
            .width = @intCast(glyph_bitmap.width),
            .height = @intCast(glyph_bitmap.height),
            .off_x = glyph_bitmap.left,
            .off_y = glyph_bitmap.top,
        };
    }

    /// Get horizontal metrics (compatible with TrueType)
    pub fn glyphHMetrics(self: Font, glyph_index: u32) HMetrics {
        // Load the glyph to get metrics
        if (c.FT_Load_Glyph(self.face.face, glyph_index, c.FT_LOAD_DEFAULT) != 0) {
            return HMetrics{ .advance_width = 0, .left_side_bearing = 0 };
        }

        const metrics = self.face.getGlyphMetrics() orelse {
            return HMetrics{ .advance_width = 0, .left_side_bearing = 0 };
        };

        return HMetrics{
            .advance_width = @intCast(metrics.hori_advance >> 6), // Convert from 26.6 format
            .left_side_bearing = @intCast(metrics.hori_bearing_x >> 6),
        };
    }
};

/// Glyph dimensions (compatible with TrueType)
pub const GlyphDimensions = struct {
    width: i32,
    height: i32,
    off_x: i32,
    off_y: i32,
};

/// Horizontal metrics (compatible with TrueType)
pub const HMetrics = struct {
    advance_width: i32,
    left_side_bearing: i32,
};

/// Load a font from memory (top-level function compatible with TrueType.load)
pub fn load(font_data: []const u8) FreeTypeError!Font {
    return Font.init(font_data);
}