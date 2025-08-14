# C++ Font Class to Zig Translation Guide

This document shows how the C++ Font class methods and features map to the Zig vector font renderer implementation in `src/render/font.zig`.

## Class Structure Mapping

### C++ Font Class
```cpp
class Font {
    struct Glyph { ... };
    struct BufferGlyph { ... };
    struct BufferCurve { ... };
    struct BufferVertex { ... };
    
    // Static methods
    static FT_Face loadFace(...);
    
    // Constructor/Destructor
    Font(FT_Face face, float worldSize, bool hinting);
    ~Font();
    
    // Public methods
    void setWorldSize(float worldSize);
    void prepareGlyphsForText(const std::string& text);
    void drawSetup();
    void draw(float x, float y, const std::string& text);
    BoundingBox measure(float x, float y, const std::string& text);
};
```

### Zig font.Renderer
```zig
pub const Renderer = struct {
    const Glyph = struct { ... };
    const BufferGlyph = struct { ... };
    const BufferCurve = struct { ... };
    const Element = struct { ... }; // Similar to BufferVertex
    
    // Constructor/Destructor equivalent
    pub fn new(allocator: std.mem.Allocator) Renderer;
    pub fn cleanup(self: *Renderer) void;
    pub fn setup(self: *Renderer, args: SetupArgs) !void;
    
    // Public methods
    pub fn setWorldSize(self: *Renderer, world_size: f32) !void;
    pub fn prepareGlyphsForText(self: *Renderer, text: []const u8) !void;
    pub fn drawSetup(self: *Renderer) void;
    pub fn addLine(self: *Renderer, text: []const u8, x: f32, y: f32, color: sg.Color) void;
    pub fn measureText(self: *Renderer, text: []const u8, x: f32, y: f32) BoundingBox;
};
```

## Method-by-Method Translation

| C++ Method | Zig Equivalent | Notes |
|------------|----------------|-------|
| `Font::loadFace()` | `freetype.load()` | Static function moved to freetype module |
| `Font(face, worldSize, hinting)` | `setup(SetupArgs{.face, .world_size, .hinting})` | Two-phase initialization in Zig |
| `~Font()` | `cleanup()` | Manual cleanup required |
| `setWorldSize(size)` | `setWorldSize(size)` | Direct equivalent, returns error |
| `prepareGlyphsForText(text)` | `prepareGlyphsForText(text)` | Direct equivalent, returns error |
| `drawSetup()` | `drawSetup()` | Direct equivalent |
| `draw(x, y, text)` | `addLine(text, x, y, color)` | Enhanced with color parameter |
| `measure(x, y, text)` | `measureText(text, x, y)` | Direct equivalent with reordered params |

## Additional Zig API Enhancements

The Zig implementation provides several convenience methods not present in the C++ version:

```zig
// Drawing methods
pub fn draw(self: *Renderer, x: f32, y: f32, text: []const u8, color: sg.Color) void;
pub fn drawAndMeasure(self: *Renderer, x: f32, y: f32, text: []const u8, color: sg.Color) f32;

// Utility methods
pub fn getSpaceAdvance(self: *Renderer) f32;
pub fn hasGlyph(self: *Renderer, charcode: u32) bool;
pub fn getLineHeight(self: *Renderer) f32;

// Buffer management (similar to C++ private methods)
pub fn updateBuffer(self: Renderer) void;
pub fn clear(self: *Renderer) void;
pub fn renderInPass(self: Renderer, vs_range: sg.Range) void;
```

## Usage Pattern Comparison

### C++ Usage
```cpp
// Initialize
FT_Library library;
FT_Init_FreeType(&library);
std::string error;
FT_Face face = Font::loadFace(library, "font.ttf", error);
Font font(face, 16.0f, true);

// Setup for rendering
font.drawSetup();

// Render text
font.draw(100.0f, 200.0f, "Hello, World!");

// Measure text
Font::BoundingBox bbox = font.measure(100.0f, 200.0f, "Hello, World!");

// Prepare additional glyphs
font.prepareGlyphsForText("New text with new characters");

// Change size
font.setWorldSize(24.0f);
```

### Zig Usage
```zig
// Initialize
const font_data = @embedFile("font.ttf");
const face = try freetype.load(font_data);
var font_renderer = font.Renderer.new(allocator);
defer font_renderer.cleanup();

try font_renderer.setup(.{
    .face = face,
    .world_size = 16.0,
    .hinting = true,
});

// Render text
font_renderer.clear(); // Start of frame
const white = sg.Color{ .r = 1, .g = 1, .b = 1, .a = 1 };
font_renderer.draw(100.0, 200.0, "Hello, World!", white);
font_renderer.updateBuffer();

// In render loop
font_renderer.renderInPass(vs_uniforms);

// Measure text
const bbox = font_renderer.measureText("Hello, World!", 100.0, 200.0);

// Prepare additional glyphs
try font_renderer.prepareGlyphsForText("New text with new characters");

// Change size
try font_renderer.setWorldSize(24.0);
```

## Key Differences

### 1. Error Handling
- **C++**: Uses return values and output parameters for errors
- **Zig**: Uses error unions (`!void`, `!f32`) for explicit error handling

### 2. Memory Management
- **C++**: RAII with automatic cleanup in destructor
- **Zig**: Manual cleanup with `defer` pattern recommended

### 3. String Handling
- **C++**: Uses `std::string`
- **Zig**: Uses `[]const u8` (byte slices)

### 4. Color Support
- **C++**: No built-in color support (handled externally)
- **Zig**: Integrated `sg.Color` parameter in rendering methods

### 5. Unicode Handling
- **C++**: Manual UTF-8 decoding with `decodeCharcode`
- **Zig**: Built-in UTF-8 support with `std.unicode`

### 6. Buffer Management
- **C++**: Automatic buffer uploads in `draw()`
- **Zig**: Explicit `updateBuffer()` call required for performance

## Shader Integration

### C++ Shader Setup
```cpp
font.program = shader_program_id; // Set externally
font.drawSetup(); // Binds textures and uniforms
```

### Zig Shader Integration
```zig
// Shaders are compiled and integrated automatically
font_renderer.renderInPass(vs_uniforms); // Complete render pass
// or manual control:
font_renderer.drawSetup(); // Setup only
sg.applyUniforms(shd_font.UB_vs_params, vs_uniforms);
sg.draw(0, 6, element_count);
```

## Performance Considerations

1. **Glyph Preparation**: Both versions support dynamic glyph loading, but Zig version provides better error handling
2. **Buffer Updates**: Zig version gives explicit control over when GPU buffers are updated
3. **Memory Allocation**: Zig version uses an explicit allocator pattern for better memory control
4. **Render Batching**: Both versions support batching multiple text elements in a single draw call

## Migration Tips

1. Replace `std::string` with `[]const u8`
2. Use `try` for error-returning functions
3. Add explicit `updateBuffer()` calls after text changes
4. Use `defer font_renderer.cleanup()` for automatic cleanup
5. Handle errors explicitly rather than checking return codes
6. Use `sg.Color` struct instead of external color management

This mapping should help you understand how the existing Zig implementation provides all the functionality of your C++ Font class with idiomatic Zig patterns and additional convenience features.
