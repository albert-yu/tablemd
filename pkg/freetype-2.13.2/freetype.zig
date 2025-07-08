const std = @import("std");

// FreeType C API bindings
pub const c = @cImport({
    @cInclude("ft2build.h");
    @cInclude("freetype/freetype.h");
    @cInclude("freetype/ftglyph.h");
    @cInclude("freetype/ftbitmap.h");
    @cInclude("freetype/ftstroke.h");
    @cInclude("freetype/ftsynth.h");
    @cInclude("freetype/ftoutln.h");
    @cInclude("freetype/ftbbox.h");
    @cInclude("freetype/ftmodapi.h");
    @cInclude("freetype/ftrender.h");
    @cInclude("freetype/ftsizes.h");
    @cInclude("freetype/fttrigon.h");
    @cInclude("freetype/ftgasp.h");
    @cInclude("freetype/ftmm.h");
    @cInclude("freetype/ftcolor.h");
});

// Error handling
pub const Error = error{
    CannotOpenResource,
    UnknownFileFormat,
    InvalidFileFormat,
    InvalidVersion,
    LowerModuleVersion,
    InvalidArgument,
    UnimplementedFeature,
    InvalidTable,
    InvalidOffset,
    ArrayTooLarge,
    MissingModule,
    MissingProperty,
    InvalidGlyphIndex,
    InvalidCharacterCode,
    InvalidGlyphFormat,
    CannotRenderGlyph,
    InvalidOutline,
    InvalidComposite,
    TooManyHints,
    InvalidPixelSize,
    InvalidHandle,
    InvalidLibraryHandle,
    InvalidDriverHandle,
    InvalidFaceHandle,
    InvalidSizeHandle,
    InvalidSlotHandle,
    InvalidCharMapHandle,
    InvalidCacheHandle,
    InvalidStreamHandle,
    TooManyDrivers,
    TooManyExtensions,
    OutOfMemory,
    UnlistedObject,
    CannotOpenStream,
    InvalidStreamSeek,
    InvalidStreamSkip,
    InvalidStreamRead,
    InvalidStreamOperation,
    InvalidFrameOperation,
    NestedFrameAccess,
    InvalidFrameRead,
    RasterUninitialized,
    RasterCorrupted,
    RasterOverflow,
    RasterNegativeHeight,
    TooManyCaches,
    InvalidOpcode,
    TooFewArguments,
    StackOverflow,
    CodeOverflow,
    BadArgument,
    DivideByZero,
    InvalidReference,
    DebugOpCode,
    ENDFInExecStream,
    NestedDEFS,
    InvalidCodeRange,
    ExecutionTooLong,
    TooManyFunctionDefs,
    TooManyInstructionDefs,
    TableMissing,
    HorizHeaderMissing,
    LocationsMissing,
    NameTableMissing,
    CMapTableMissing,
    HmtxTableMissing,
    PostTableMissing,
    InvalidHorizMetrics,
    InvalidCharMapFormat,
    InvalidPPem,
    InvalidVertMetrics,
    CouldNotFindContext,
    InvalidPostTableFormat,
    InvalidPostTable,
    SyntaxError,
    StackUnderflow,
    Ignore,
    NoUnicodeGlyphName,
    MissingStartfontField,
    MissingFontField,
    MissingSizeField,
    MissingFontboundingboxField,
    MissingCharsField,
    MissingStartcharField,
    MissingEncodingField,
    MissingBbxField,
    BbxTooBig,
    CorruptedFontHeader,
    CorruptedFontGlyphs,
    Unknown,
};

fn errorFromCode(code: c.FT_Error) Error {
    return switch (code) {
        0x01 => Error.CannotOpenResource,
        0x02 => Error.UnknownFileFormat,
        0x03 => Error.InvalidFileFormat,
        0x04 => Error.InvalidVersion,
        0x05 => Error.LowerModuleVersion,
        0x06 => Error.InvalidArgument,
        0x07 => Error.UnimplementedFeature,
        0x08 => Error.InvalidTable,
        0x09 => Error.InvalidOffset,
        0x0A => Error.ArrayTooLarge,
        0x0B => Error.MissingModule,
        0x0C => Error.MissingProperty,
        0x10 => Error.InvalidGlyphIndex,
        0x11 => Error.InvalidCharacterCode,
        0x12 => Error.InvalidGlyphFormat,
        0x13 => Error.CannotRenderGlyph,
        0x14 => Error.InvalidOutline,
        0x15 => Error.InvalidComposite,
        0x16 => Error.TooManyHints,
        0x17 => Error.InvalidPixelSize,
        0x20 => Error.InvalidHandle,
        0x21 => Error.InvalidLibraryHandle,
        0x22 => Error.InvalidDriverHandle,
        0x23 => Error.InvalidFaceHandle,
        0x24 => Error.InvalidSizeHandle,
        0x25 => Error.InvalidSlotHandle,
        0x26 => Error.InvalidCharMapHandle,
        0x27 => Error.InvalidCacheHandle,
        0x28 => Error.InvalidStreamHandle,
        0x30 => Error.TooManyDrivers,
        0x31 => Error.TooManyExtensions,
        0x40 => Error.OutOfMemory,
        0x41 => Error.UnlistedObject,
        0x51 => Error.CannotOpenStream,
        0x52 => Error.InvalidStreamSeek,
        0x53 => Error.InvalidStreamSkip,
        0x54 => Error.InvalidStreamRead,
        0x55 => Error.InvalidStreamOperation,
        0x56 => Error.InvalidFrameOperation,
        0x57 => Error.NestedFrameAccess,
        0x58 => Error.InvalidFrameRead,
        0x60 => Error.RasterUninitialized,
        0x61 => Error.RasterCorrupted,
        0x62 => Error.RasterOverflow,
        0x63 => Error.RasterNegativeHeight,
        0x70 => Error.TooManyCaches,
        0x80 => Error.InvalidOpcode,
        0x81 => Error.TooFewArguments,
        0x82 => Error.StackOverflow,
        0x83 => Error.CodeOverflow,
        0x84 => Error.BadArgument,
        0x85 => Error.DivideByZero,
        0x86 => Error.InvalidReference,
        0x87 => Error.DebugOpCode,
        0x88 => Error.ENDFInExecStream,
        0x89 => Error.NestedDEFS,
        0x8A => Error.InvalidCodeRange,
        0x8B => Error.ExecutionTooLong,
        0x8C => Error.TooManyFunctionDefs,
        0x8D => Error.TooManyInstructionDefs,
        0x8E => Error.TableMissing,
        0x8F => Error.HorizHeaderMissing,
        0x90 => Error.LocationsMissing,
        0x91 => Error.NameTableMissing,
        0x92 => Error.CMapTableMissing,
        0x93 => Error.HmtxTableMissing,
        0x94 => Error.PostTableMissing,
        0x95 => Error.InvalidHorizMetrics,
        0x96 => Error.InvalidCharMapFormat,
        0x97 => Error.InvalidPPem,
        0x98 => Error.InvalidVertMetrics,
        0x99 => Error.CouldNotFindContext,
        0x9A => Error.InvalidPostTableFormat,
        0x9B => Error.InvalidPostTable,
        0xA0 => Error.SyntaxError,
        0xA1 => Error.StackUnderflow,
        0xA2 => Error.Ignore,
        0xA3 => Error.NoUnicodeGlyphName,
        0xB0 => Error.MissingStartfontField,
        0xB1 => Error.MissingFontField,
        0xB2 => Error.MissingSizeField,
        0xB3 => Error.MissingFontboundingboxField,
        0xB4 => Error.MissingCharsField,
        0xB5 => Error.MissingStartcharField,
        0xB6 => Error.MissingEncodingField,
        0xB7 => Error.MissingBbxField,
        0xB8 => Error.BbxTooBig,
        0xB9 => Error.CorruptedFontHeader,
        0xBA => Error.CorruptedFontGlyphs,
        else => Error.Unknown,
    };
}

pub fn checkError(code: c.FT_Error) Error!void {
    if (code != 0) {
        return errorFromCode(code);
    }
}

// Library wrapper
pub const Library = struct {
    handle: c.FT_Library,

    pub fn init() Error!Library {
        var library: c.FT_Library = undefined;
        const err = c.FT_Init_FreeType(&library);
        try checkError(err);
        return Library{ .handle = library };
    }

    pub fn deinit(self: Library) void {
        _ = c.FT_Done_FreeType(self.handle);
    }

    pub fn newFace(self: Library, filepath: []const u8, face_index: c.FT_Long) Error!Face {
        var face: c.FT_Face = undefined;
        const err = c.FT_New_Face(self.handle, filepath.ptr, face_index, &face);
        try checkError(err);
        return Face{ .handle = face };
    }

    pub fn newMemoryFace(self: Library, file_base: []const u8, face_index: c.FT_Long) Error!Face {
        var face: c.FT_Face = undefined;
        const err = c.FT_New_Memory_Face(self.handle, file_base.ptr, @intCast(file_base.len), face_index, &face);
        try checkError(err);
        return Face{ .handle = face };
    }
};

// Face wrapper
pub const Face = struct {
    handle: c.FT_Face,

    pub fn deinit(self: Face) void {
        _ = c.FT_Done_Face(self.handle);
    }

    pub fn setCharSize(self: Face, char_width: c.FT_F26Dot6, char_height: c.FT_F26Dot6, horz_resolution: c.FT_UInt, vert_resolution: c.FT_UInt) Error!void {
        const err = c.FT_Set_Char_Size(self.handle, char_width, char_height, horz_resolution, vert_resolution);
        try checkError(err);
    }

    pub fn setPixelSizes(self: Face, pixel_width: c.FT_UInt, pixel_height: c.FT_UInt) Error!void {
        const err = c.FT_Set_Pixel_Sizes(self.handle, pixel_width, pixel_height);
        try checkError(err);
    }

    pub fn getCharIndex(self: Face, charcode: c.FT_ULong) c.FT_UInt {
        return c.FT_Get_Char_Index(self.handle, charcode);
    }

    pub fn loadGlyph(self: Face, glyph_index: c.FT_UInt, load_flags: c.FT_Int32) Error!void {
        const err = c.FT_Load_Glyph(self.handle, glyph_index, load_flags);
        try checkError(err);
    }

    pub fn loadChar(self: Face, char_code: c.FT_ULong, load_flags: c.FT_Int32) Error!void {
        const err = c.FT_Load_Char(self.handle, char_code, load_flags);
        try checkError(err);
    }

    pub fn renderGlyph(self: Face, render_mode: c.FT_Render_Mode) Error!void {
        const err = c.FT_Render_Glyph(self.handle.*.glyph, render_mode);
        try checkError(err);
    }

    pub fn getKerning(self: Face, left_glyph: c.FT_UInt, right_glyph: c.FT_UInt, kern_mode: c.FT_UInt) Error!c.FT_Vector {
        var kerning: c.FT_Vector = undefined;
        const err = c.FT_Get_Kerning(self.handle, left_glyph, right_glyph, kern_mode, &kerning);
        try checkError(err);
        return kerning;
    }

    pub fn getGlyph(self: Face) Error!Glyph {
        var glyph: c.FT_Glyph = undefined;
        const err = c.FT_Get_Glyph(self.handle.*.glyph, &glyph);
        try checkError(err);
        return Glyph{ .handle = glyph };
    }

    pub fn getGlyphSlot(self: Face) GlyphSlot {
        return GlyphSlot{ .handle = self.handle.*.glyph };
    }

    pub fn getNumFaces(self: Face) c.FT_Long {
        return self.handle.*.num_faces;
    }

    pub fn getFaceIndex(self: Face) c.FT_Long {
        return self.handle.*.face_index;
    }

    pub fn getNumGlyphs(self: Face) c.FT_Long {
        return self.handle.*.num_glyphs;
    }

    pub fn getFamilyName(self: Face) ?[]const u8 {
        const name_ptr = self.handle.*.family_name;
        if (name_ptr) |ptr| {
            return std.mem.span(ptr);
        }
        return null;
    }

    pub fn getStyleName(self: Face) ?[]const u8 {
        const name_ptr = self.handle.*.style_name;
        if (name_ptr) |ptr| {
            return std.mem.span(ptr);
        }
        return null;
    }

    pub fn getUnitsPerEM(self: Face) c.FT_UShort {
        return self.handle.*.units_per_EM;
    }

    pub fn getAscender(self: Face) c.FT_Short {
        return self.handle.*.ascender;
    }

    pub fn getDescender(self: Face) c.FT_Short {
        return self.handle.*.descender;
    }

    pub fn getHeight(self: Face) c.FT_Short {
        return self.handle.*.height;
    }

    pub fn getMaxAdvanceWidth(self: Face) c.FT_Short {
        return self.handle.*.max_advance_width;
    }

    pub fn getMaxAdvanceHeight(self: Face) c.FT_Short {
        return self.handle.*.max_advance_height;
    }
};

// Glyph wrapper
pub const Glyph = struct {
    handle: c.FT_Glyph,

    pub fn deinit(self: Glyph) void {
        c.FT_Done_Glyph(self.handle);
    }

    pub fn copy(self: Glyph) Error!Glyph {
        var glyph: c.FT_Glyph = undefined;
        const err = c.FT_Glyph_Copy(self.handle, &glyph);
        try checkError(err);
        return Glyph{ .handle = glyph };
    }

    pub fn getBBox(self: Glyph, bbox_mode: c.FT_UInt) Error!c.FT_BBox {
        var bbox: c.FT_BBox = undefined;
        const err = c.FT_Glyph_Get_CBox(self.handle, bbox_mode, &bbox);
        try checkError(err);
        return bbox;
    }

    pub fn transform(self: Glyph, matrix: ?*c.FT_Matrix, delta: ?*c.FT_Vector) Error!void {
        const err = c.FT_Glyph_Transform(self.handle, matrix, delta);
        try checkError(err);
    }

    pub fn toBitmap(self: Glyph, render_mode: c.FT_Render_Mode, origin: ?*c.FT_Vector, destroy: bool) Error!BitmapGlyph {
        var glyph = self.handle;
        const err = c.FT_Glyph_To_Bitmap(&glyph, render_mode, origin, if (destroy) 1 else 0);
        try checkError(err);
        return BitmapGlyph{ .handle = @ptrCast(glyph) };
    }
};

// BitmapGlyph wrapper
pub const BitmapGlyph = struct {
    handle: c.FT_BitmapGlyph,

    pub fn getBitmap(self: BitmapGlyph) *c.FT_Bitmap {
        return &self.handle.*.bitmap;
    }

    pub fn getLeft(self: BitmapGlyph) c.FT_Int {
        return self.handle.*.left;
    }

    pub fn getTop(self: BitmapGlyph) c.FT_Int {
        return self.handle.*.top;
    }
};

// GlyphSlot wrapper
pub const GlyphSlot = struct {
    handle: c.FT_GlyphSlot,

    pub fn getBitmap(self: GlyphSlot) *c.FT_Bitmap {
        return &self.handle.*.bitmap;
    }

    pub fn getBitmapLeft(self: GlyphSlot) c.FT_Int {
        return self.handle.*.bitmap_left;
    }

    pub fn getBitmapTop(self: GlyphSlot) c.FT_Int {
        return self.handle.*.bitmap_top;
    }

    pub fn getAdvance(self: GlyphSlot) c.FT_Vector {
        return self.handle.*.advance;
    }

    pub fn getMetrics(self: GlyphSlot) c.FT_Glyph_Metrics {
        return self.handle.*.metrics;
    }

    pub fn getLinearHoriAdvance(self: GlyphSlot) c.FT_Fixed {
        return self.handle.*.linearHoriAdvance;
    }

    pub fn getLinearVertAdvance(self: GlyphSlot) c.FT_Fixed {
        return self.handle.*.linearVertAdvance;
    }

    pub fn getOutline(self: GlyphSlot) *c.FT_Outline {
        return &self.handle.*.outline;
    }

    pub fn getFormat(self: GlyphSlot) c.FT_Glyph_Format {
        return self.handle.*.format;
    }
};

// Bitmap wrapper
pub const Bitmap = struct {
    handle: *c.FT_Bitmap,

    pub fn getRows(self: Bitmap) c.FT_UInt {
        return self.handle.rows;
    }

    pub fn getWidth(self: Bitmap) c.FT_UInt {
        return self.handle.width;
    }

    pub fn getPitch(self: Bitmap) c.FT_Int {
        return self.handle.pitch;
    }

    pub fn getBuffer(self: Bitmap) []u8 {
        const size = @as(usize, @intCast(@abs(self.handle.pitch))) * self.handle.rows;
        return self.handle.buffer[0..size];
    }

    pub fn getPixelMode(self: Bitmap) c.FT_Pixel_Mode {
        return self.handle.pixel_mode;
    }

    pub fn getNumGrays(self: Bitmap) c.FT_UChar {
        return self.handle.num_grays;
    }
};

// Utility functions
pub fn versionString() []const u8 {
    var major: c.FT_Int = undefined;
    var minor: c.FT_Int = undefined;
    var patch: c.FT_Int = undefined;
    c.FT_Library_Version(null, &major, &minor, &patch);

    // This is a simplified version string - you might want to format this properly
    return "FreeType";
}

// Common constants
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
pub const LOAD_COLOR = c.FT_LOAD_COLOR;
pub const LOAD_COMPUTE_METRICS = c.FT_LOAD_COMPUTE_METRICS;

pub const RENDER_MODE_NORMAL = c.FT_RENDER_MODE_NORMAL;
pub const RENDER_MODE_LIGHT = c.FT_RENDER_MODE_LIGHT;
pub const RENDER_MODE_MONO = c.FT_RENDER_MODE_MONO;
pub const RENDER_MODE_LCD = c.FT_RENDER_MODE_LCD;
pub const RENDER_MODE_LCD_V = c.FT_RENDER_MODE_LCD_V;

pub const PIXEL_MODE_NONE = c.FT_PIXEL_MODE_NONE;
pub const PIXEL_MODE_MONO = c.FT_PIXEL_MODE_MONO;
pub const PIXEL_MODE_GRAY = c.FT_PIXEL_MODE_GRAY;
pub const PIXEL_MODE_GRAY2 = c.FT_PIXEL_MODE_GRAY2;
pub const PIXEL_MODE_GRAY4 = c.FT_PIXEL_MODE_GRAY4;
pub const PIXEL_MODE_LCD = c.FT_PIXEL_MODE_LCD;
pub const PIXEL_MODE_LCD_V = c.FT_PIXEL_MODE_LCD_V;

pub const KERNING_DEFAULT = c.FT_KERNING_DEFAULT;
pub const KERNING_UNFITTED = c.FT_KERNING_UNFITTED;
pub const KERNING_UNSCALED = c.FT_KERNING_UNSCALED;

pub const GLYPH_BBOX_UNSCALED = c.FT_GLYPH_BBOX_UNSCALED;
pub const GLYPH_BBOX_SUBPIXELS = c.FT_GLYPH_BBOX_SUBPIXELS;
pub const GLYPH_BBOX_GRIDFIT = c.FT_GLYPH_BBOX_GRIDFIT;
pub const GLYPH_BBOX_TRUNCATE = c.FT_GLYPH_BBOX_TRUNCATE;
pub const GLYPH_BBOX_PIXELS = c.FT_GLYPH_BBOX_PIXELS;

// Fixed-point conversion utilities
pub fn fromFixed(value: c.FT_Fixed) f32 {
    return @as(f32, @floatFromInt(value)) / 65536.0;
}

pub fn toFixed(value: f32) c.FT_Fixed {
    return @as(c.FT_Fixed, @intFromFloat(value * 65536.0));
}

pub fn from26Dot6(value: c.FT_F26Dot6) f32 {
    return @as(f32, @floatFromInt(value)) / 64.0;
}

pub fn to26Dot6(value: f32) c.FT_F26Dot6 {
    return @as(c.FT_F26Dot6, @intFromFloat(value * 64.0));
}
