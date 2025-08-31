# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code)
when working with code in this repository.

## Project Overview

TableMD is a simple markdown table editor built in Zig
using the Sokol graphics library. It's designed for fast
startup time and ease of use. It is primarily intended to
run in the browser, but it can be built for native for ease
of debugging.

## Development Commands

### Building and Running

- **Development build (native)**: `zig build run`
- **Web build (development)**:
`zig build -Dtarget=wasm32-emscripten --release=safe run`
  - Note: There's currently a bug in Zig's wasm32-emscripten
  target where non-release builds complain about a missing base pointer,
  so `--release=[mode]` is required
  - Automatically opens a browser window with the app running

### Deployment

- **Bundle for deployment**: `./bundle.sh`
  - Automatically installs Zig if not present (with checksum verification)
  - Builds the web version and copies static files to `dist/` directory
  - Renames `root.html` to `index.html` for web deployment
  - Can be deployed to Cloudflare Pages (see `wrangler.toml`)

## Architecture

### Core Structure

- **Entry point**: `src/root.zig` - Main application logic with Sokol app lifecycle
- **Rendering system**: Modular renderer architecture in `src/render/`
  - `dot_grid.zig` - Grid background renderer
  - `rect.zig` - Rectangle/shape renderer
  - `font.zig` - Text rendering with FreeType under the hood
- **Graphics**: Uses Sokol for cross-platform graphics (OpenGL/WebGL/Metal/D3D11)
- **Shaders**: GLSL shaders in `src/shaders/` compiled via sokol-shdc
- **Math**: Uses zm library for vector/matrix operations

### Key Dependencies

- **Sokol**: Cross-platform graphics/app framework
- **FreeType (vendored)**: Font loading and rendering
- **zm**: Math library for vectors and matrices

### Coordinate System & Interaction

- Uses transform matrices for pan/zoom functionality (`src/uniforms.zig`)
- Supports both mouse and multi-touch input (pinch-to-zoom, pan gestures)
- Grid-based cell positioning system for table editing
- Coordinate transformation between screen space and grid space

### Build System

- Zig's native build system (`build.zig`)
- Shader compilation pipeline that generates Zig modules from GLSL
- Conditional compilation for native vs web targets
- Web builds use Emscripten linker with custom HTML shell (`src/web/shell.html`)

### Current State

The application supports basic table editing functionality:

- Add/remove cells
- Edit UTF-8 text
- Extend tables by editing adjacent cells
- Paste text from clipboard
- Pan/zoom

## File Structure Notes

- Font assets in `src/fonts/`
- Build output goes to `zig-out/` (native) or `zig-out/web/` (web)
- Deployment artifacts are copied to `dist/` by bundle script
- No package.json - this is a pure Zig project using Zig's package manager
