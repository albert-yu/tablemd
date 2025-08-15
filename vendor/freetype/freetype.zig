const std = @import("std");

// FreeType C bindings
pub const c = @cImport({
    @cInclude("ft2build.h");
    @cInclude("freetype/freetype.h");
    @cInclude("freetype/ftglyph.h");
    @cInclude("freetype/ftbitmap.h");
    @cInclude("freetype/ftoutln.h");
});

pub const uint = c.FT_UInt;
pub const pos = c.FT_Pos;

// Type aliases
pub const Outline = c.FT_Outline;
pub const Vector = c.FT_Vector;

// Outline flags
pub const OUTLINE_REVERSE_FILL = c.FT_OUTLINE_REVERSE_FILL;

// Curve tags
pub const CURVE_TAG_ON = c.FT_CURVE_TAG_ON;
pub const CURVE_TAG_CUBIC = c.FT_CURVE_TAG_CUBIC;
pub const CURVE_TAG_CONIC = c.FT_CURVE_TAG_CONIC;

pub const KerningMode = enum(c.enum_FT_Kerning_Mode_) {
    default = c.FT_KERNING_DEFAULT,
    unfitted = c.FT_KERNING_UNFITTED,
    unscaled = c.FT_KERNING_UNSCALED,
};

pub const LoadFlags = c_int;

pub const LOAD_DEFAULT = c.FT_LOAD_DEFAULT;
pub const LOAD_NO_SCALE = c.FT_LOAD_NO_SCALE;
pub const LOAD_NO_HINTING = c.FT_LOAD_NO_HINTING;
pub const LOAD_RENDER = c.FT_LOAD_RENDER;
pub const LOAD_NO_BITMAP = c.FT_LOAD_NO_BITMAP;
pub const LOAD_VERTICAL_LAYOUT = c.FT_LOAD_VERTICAL_LAYOUT;
pub const LOAD_FORCE_AUTOHINT = c.FT_LOAD_FORCE_AUTOHINT;
pub const LOAD_CROP_BITMAP = c.FT_LOAD_CROP_BITMAP;
pub const LOAD_PEDANTIC = c.FT_LOAD_PEDANTIC;
pub const LOAD_IGNORE_GLOBAL_ADVANCE_WIDTH = c.FT_LOAD_IGNORE_GLOBAL_ADVANCE_WIDTH;
pub const LOAD_NO_RECURSE = c.FT_LOAD_NO_RECURSE;
pub const LOAD_IGNORE_TRANSFORM = c.FT_LOAD_IGNORE_TRANSFORM;
pub const LOAD_MONOCHROME = c.FT_LOAD_MONOCHROME;
pub const LOAD_LINEAR_DESIGN = c.FT_LOAD_LINEAR_DESIGN;
pub const LOAD_NO_AUTOHINT = c.FT_LOAD_NO_AUTOHINT;

pub const FreeTypeError = error{
    InitError,
    LoadFaceError,
    SetSizeError,
    LoadGlyphError,
    RenderGlyphError,
    GetGlyphError,
    OutOfMemory,
    OutlineError,
    GetKerningError,
};

/// Outline point types
pub const OutlinePointType = enum(u8) {
    on_curve = 1,
    off_curve_conic = 0,
    off_curve_cubic = 2,
};

/// Outline point with type information
pub const OutlinePoint = struct {
    x: f32,
    y: f32,
    type: OutlinePointType,
};

/// Contour information for outline processing
pub const Contour = struct {
    points: []OutlinePoint,
    closed: bool,
};

/// Quadratic bezier curve for GPU rendering
pub const QuadCurve = struct {
    p0: [2]f32, // Start point
    p1: [2]f32, // Control point
    p2: [2]f32, // End point
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

    pub fn loadGlyph(self: Face, glyph_index: u32, load_flags: i32) FreeTypeError!void {
        if (c.FT_Load_Glyph(self.face, glyph_index, load_flags) != 0) {
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

    pub fn getKerning(self: Face, left_glyph: u32, right_glyph: u32, kern_mode: KerningMode) FreeTypeError!Vector {
        var kerning: Vector = undefined;
        if (c.FT_Get_Kerning(self.face, left_glyph, right_glyph, @intFromEnum(kern_mode), &kerning) != 0) {
            return FreeTypeError.GetKerningError;
        }
        return kerning;
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

    /// Extract glyph outline as contours
    pub fn getGlyphOutline(self: Face, allocator: std.mem.Allocator, glyph_index: u32) FreeTypeError![]Contour {
        // Load glyph without bitmap rendering
        if (c.FT_Load_Glyph(self.face, glyph_index, c.FT_LOAD_NO_BITMAP) != 0) {
            return FreeTypeError.LoadGlyphError;
        }

        const glyph = self.face.*.glyph;
        if (glyph.*.format != c.FT_GLYPH_FORMAT_OUTLINE) {
            return FreeTypeError.OutlineError;
        }

        const outline = &glyph.*.outline;
        if (outline.n_points == 0) {
            return &[_]Contour{};
        }

        var contours = std.ArrayList(Contour).init(allocator);
        errdefer {
            for (contours.items) |contour| {
                allocator.free(contour.points);
            }
            contours.deinit();
        }

        var start_idx: usize = 0;
        for (0..@intCast(outline.n_contours)) |contour_idx| {
            const end_idx = @as(usize, @intCast(outline.contours[contour_idx])) + 1;
            const point_count = end_idx - start_idx;

            var points = try allocator.alloc(OutlinePoint, point_count);
            errdefer allocator.free(points);

            for (start_idx..end_idx) |i| {
                const point_idx = i;
                const ft_point = outline.points[point_idx];
                const tag = outline.tags[point_idx];

                // Convert from 26.6 fixed point to float
                const x = @as(f32, @floatFromInt(ft_point.x)) / 64.0;
                const y = @as(f32, @floatFromInt(ft_point.y)) / 64.0;

                // Determine point type from FreeType tags
                const point_type: OutlinePointType = if ((tag & 1) != 0)
                    .on_curve
                else if ((tag & 2) != 0)
                    .off_curve_cubic
                else
                    .off_curve_conic;

                points[point_idx - start_idx] = OutlinePoint{
                    .x = x,
                    .y = y,
                    .type = point_type,
                };
            }

            try contours.append(Contour{
                .points = points,
                .closed = true, // TrueType contours are always closed
            });

            start_idx = end_idx;
        }

        return contours.toOwnedSlice();
    }

    /// Convert outline contours to quadratic bezier curves for GPU rendering
    pub fn outlineToQuadCurves(allocator: std.mem.Allocator, contours: []const Contour) FreeTypeError![]QuadCurve {
        var curves = std.ArrayList(QuadCurve).init(allocator);
        errdefer curves.deinit();

        for (contours) |contour| {
            if (contour.points.len < 2) continue;

            var i: usize = 0;
            while (i < contour.points.len) {
                const current = contour.points[i];
                const next_idx = if (i + 1 < contour.points.len) i + 1 else 0;
                const next = contour.points[next_idx];

                if (current.type == .on_curve) {
                    if (next.type == .on_curve) {
                        // Line segment - convert to degenerate quadratic
                        try curves.append(QuadCurve{
                            .p0 = .{ current.x, current.y },
                            .p1 = .{ (current.x + next.x) / 2.0, (current.y + next.y) / 2.0 },
                            .p2 = .{ next.x, next.y },
                        });
                        i += 1;
                    } else if (next.type == .off_curve_conic) {
                        // Quadratic bezier curve
                        const after_next_idx = if (i + 2 < contour.points.len) i + 2 else if (contour.closed) 0 else i + 1;
                        var end_point = contour.points[after_next_idx];

                        // If the end point is also off-curve, create implied on-curve point
                        if (end_point.type == .off_curve_conic) {
                            end_point = OutlinePoint{
                                .x = (next.x + end_point.x) / 2.0,
                                .y = (next.y + end_point.y) / 2.0,
                                .type = .on_curve,
                            };
                            i += 1; // We only consumed one off-curve point
                        } else {
                            i += 2; // We consumed both off-curve and on-curve points
                        }

                        try curves.append(QuadCurve{
                            .p0 = .{ current.x, current.y },
                            .p1 = .{ next.x, next.y },
                            .p2 = .{ end_point.x, end_point.y },
                        });
                    } else {
                        // Cubic bezier - convert to quadratic approximation
                        const ctrl1 = next;
                        const ctrl2_idx = if (i + 2 < contour.points.len) i + 2 else 0;
                        const ctrl2 = contour.points[ctrl2_idx];
                        const end_idx = if (i + 3 < contour.points.len) i + 3 else if (contour.closed) 0 else i + 2;
                        const end_point = contour.points[end_idx];

                        // Simple cubic to quadratic approximation
                        const approx_ctrl_x = (ctrl1.x + ctrl2.x) / 2.0;
                        const approx_ctrl_y = (ctrl1.y + ctrl2.y) / 2.0;

                        try curves.append(QuadCurve{
                            .p0 = .{ current.x, current.y },
                            .p1 = .{ approx_ctrl_x, approx_ctrl_y },
                            .p2 = .{ end_point.x, end_point.y },
                        });
                        i += 3;
                    }
                } else {
                    // Skip orphaned off-curve points
                    i += 1;
                }
            }
        }

        return curves.toOwnedSlice();
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

    pub fn glyphFontMetrics(self: Font, glyph_index: u32) FontMetrics {
        // Load the glyph to get metrics
        if (c.FT_Load_Glyph(self.face.face, glyph_index, c.FT_LOAD_DEFAULT) != 0) {
            return FontMetrics.zero;
        }

        const metrics = self.face.getGlyphMetrics() orelse {
            return FontMetrics.zero;
        };
        return FontMetrics{
            .width = @intCast(metrics.width >> 6), // Convert from 26.6 format
            .height = @intCast(metrics.height >> 6), // Convert from 26.6 format
            .hori_bearing_x = @intCast(metrics.hori_bearing_x >> 6), // Convert from 26.6 format
            .hori_bearing_y = @intCast(metrics.hori_bearing_y >> 6), // Convert from 26.6 format
            .hori_advance = @intCast(metrics.hori_advance >> 6), // Convert from 26.6 format
            .vert_bearing_x = @intCast(metrics.vert_bearing_x >> 6), // Convert from 26.6 format
            .vert_bearing_y = @intCast(metrics.vert_bearing_y >> 6), // Convert from 26.6 format
            .vert_advance = @intCast(metrics.vert_advance >> 6), // Convert from 26.6 format
        };
    }

    /// Extract glyph outline as quadratic curves for GPU rendering
    pub fn glyphQuadCurves(self: Font, allocator: std.mem.Allocator, glyph_index: u32) FreeTypeError![]QuadCurve {
        const contours = try self.face.getGlyphOutline(allocator, glyph_index);
        defer {
            for (contours) |contour| {
                allocator.free(contour.points);
            }
            allocator.free(contours);
        }

        return Face.outlineToQuadCurves(allocator, contours);
    }
};

/// Glyph dimensions (compatible with TrueType)
pub const GlyphDimensions = struct {
    width: i32,
    height: i32,
    off_x: i32,
    off_y: i32,
};

/// Glyph metrics, but with 26.6 fixed point values
pub const FontMetrics = struct {
    width: i32,
    height: i32,
    hori_bearing_x: i32,
    hori_bearing_y: i32,
    hori_advance: i32,
    vert_bearing_x: i32,
    vert_bearing_y: i32,
    vert_advance: i32,

    pub const zero = FontMetrics{
        .width = 0,
        .height = 0,
        .hori_bearing_x = 0,
        .hori_bearing_y = 0,
        .hori_advance = 0,
        .vert_bearing_x = 0,
        .vert_bearing_y = 0,
        .vert_advance = 0,
    };
};

/// Load a font from memory (top-level function compatible with TrueType.load)
pub fn load(font_data: []const u8) FreeTypeError!Font {
    return Font.init(font_data);
}
