const std = @import("std");
const builtin = @import("builtin");
const sokol = @import("sokol");
const ui = @import("ui.zig");
const markdown = @import("markdown");
const theme = @import("theme.zig");

// External JavaScript functions
extern fn set_html_render(ptr: [*]const u8, len: usize) void;
extern fn set_markdown_source(ptr: [*]const u8, len: usize) void;
extern fn set_serialized_tables(ptr: [*]const u8, len: usize) void;
extern fn activate_mobile_keyboard() void;

const Scene = ui.Scene;
const UI = ui.UI;
const RectRenderer = @import("render/rect.zig").Renderer;
const TextRenderer = @import("render/text.zig").Renderer;
const dot_grid = @import("render/dot_grid.zig");
const DotGridRenderer = dot_grid.Renderer;
const RectDims = dot_grid.Size;
const Transform = @import("uniforms.zig").Transform;
const Vec2 = @import("zm").Vec2f;
const TrueType = @import("TrueType");

const io = std.io;
const sapp = sokol.app;
const slog = sokol.log;
const sg = sokol.gfx;
const sglue = sokol.glue;
const Color = sg.Color;

const CellPosition = struct {
    row: usize,
    col: usize,
};

const BG_COLOR: Color = theme.DARK_THEME.background_color;

const WIDTH_START = 800;
const HEIGHT_START = 600;
const TOUCH_THRESHOLD = 10.0; // pixels

// Momentum constants
const MOMENTUM_MIN_SPEED = 5.0; // Minimum speed to trigger momentum
const MOMENTUM_MAX_SPEED = 100.0; // Maximum momentum speed
const MOMENTUM_DECELERATION = 0.92; // Deceleration factor per frame (0.0-1.0)

const TouchState = struct {
    active: bool = false,
    num_touches: u32 = 0,
    touches: [10]Vec2 = [_]Vec2{Vec2{ 0, 0 }} ** 10,
    prev_touches: [10]Vec2 = [_]Vec2{Vec2{ 0, 0 }} ** 10,
    initial_distance: f32 = 0,
    prev_distance: f32 = 0,
    center: Vec2 = Vec2{ 0, 0 },
    prev_center: Vec2 = Vec2{ 0, 0 },
    // Momentum tracking
    velocity: Vec2 = Vec2{ 0, 0 },
    has_momentum: bool = false,
    momentum_samples: [5]Vec2 = [_]Vec2{Vec2{ 0, 0 }} ** 5,
    momentum_sample_index: u32 = 0,
};

const state = struct {
    var dot_grid_renderer = DotGridRenderer.new();
    var rect_renderer = RectRenderer.new();
    var text_renderer: TextRenderer = undefined;
    var pass_action: sg.PassAction = .{};
    var t = Transform.new();
    var allocator: std.mem.Allocator = undefined;
    // This is here so that deinit can deallocate.
    // For practical purposes, we do not need to
    // deallocate on shutdown, but we can leave this
    // here to make sure we don't leak memory.
    var gpa: ?std.heap.GeneralPurposeAllocator(.{}) = null;

    var mouse: [2]Vec2 = .{ Vec2{ 0, 0 }, Vec2{ 0, 0 } };
    var mouse_press_pos: ?Vec2 = null;
    var is_dragging: bool = false;
    var touch_state = TouchState{};
    var rect_dims = RectDims{ .width = 0, .height = 0 };
    var text_dims = RectDims{ .width = 0, .height = 0 };
    var scene: Scene = undefined;
    var ui: UI = undefined;
};

export fn init() void {
    sg.setup(.{
        .environment = sglue.environment(),
        .logger = .{ .func = slog.func },
    });

    state.allocator = if (builtin.target.cpu.arch.isWasm())
        std.heap.c_allocator
    else blk: {
        state.gpa = std.heap.GeneralPurposeAllocator(.{}){};
        break :blk state.gpa.?.allocator();
    };

    state.scene = Scene.init(state.allocator);

    state.t.updateZoom(.{ .k = 1.0, .x = 0.0, .y = 0.0 });

    // quad (dot grid binding and pipeline)
    const rect_dims = state.dot_grid_renderer.setup();
    state.rect_dims = rect_dims;
    state.rect_renderer.setup();

    // text renderer
    state.text_renderer = TextRenderer.new(state.allocator);
    const text_width = state.text_renderer.setup() catch |err| {
        std.log.err("Failed to setup text renderer: {}", .{err});
        return;
    };
    state.text_dims = RectDims{ .width = text_width, .height = rect_dims.height };
    state.ui = UI.init(state.allocator, .{
        .cell = .{ .width = rect_dims.width, .height = rect_dims.height },
        .text = .{ .width = text_width, .height = rect_dims.height },
    });

    // Create a simple 3x3 table
    const table = state.ui.addTable(state.allocator) catch unreachable;
    table.position = .{ .left = 1, .top = 1 };

    const col1 = table.addColumn(state.allocator) catch unreachable;
    const col2 = table.addColumn(state.allocator) catch unreachable;
    const col3 = table.addColumn(state.allocator) catch unreachable;

    // Column 1
    col1.addCell(state.allocator, "Name") catch unreachable;
    col1.addCell(state.allocator, "Alice") catch unreachable;
    col1.addCell(state.allocator, "Bob") catch unreachable;

    // Column 2
    col2.addCell(state.allocator, "Age") catch unreachable;
    col2.addCell(state.allocator, "25") catch unreachable;
    col2.addCell(state.allocator, "30") catch unreachable;

    // Column 3
    col3.addCell(state.allocator, "City") catch unreachable;
    col3.addCell(state.allocator, "NYC") catch unreachable;
    col3.addCell(state.allocator, "LA") catch unreachable;

    sendTableToDOM(table) catch |err| {
        std.log.err("Failed to send table to DOM: {}", .{err});
    };

    state.pass_action.colors[0] = .{
        .load_action = .CLEAR,
        // if we see red, something is wrong
        .clear_value = .{ .r = 1.0, .g = 0.0, .b = 0.0, .a = 1.0 },
    };

    state.t.updateWindowData(sapp.widthf(), sapp.heightf());
}

export fn frame() void {
    // Process momentum
    if (state.touch_state.has_momentum) {
        const speed = @sqrt(state.touch_state.velocity[0] * state.touch_state.velocity[0] +
            state.touch_state.velocity[1] * state.touch_state.velocity[1]);

        if (speed > 1.0) {
            // Apply momentum movement
            handlePan(state.touch_state.velocity[0], state.touch_state.velocity[1]);

            // Decelerate
            state.touch_state.velocity[0] *= MOMENTUM_DECELERATION;
            state.touch_state.velocity[1] *= MOMENTUM_DECELERATION;
        } else {
            // Stop momentum when speed is too low
            state.touch_state.has_momentum = false;
            state.touch_state.velocity = Vec2{ 0, 0 };
        }
    }

    clear();
    state.ui.addSelfToScene(state.allocator, &state.scene) catch |err| {
        std.log.err("Failed to add UI to scene: {}", .{err});
    };
    for (state.scene.rects.items) |rect| {
        state.rect_renderer.add(rect);
    }
    state.rect_renderer.updateBuffer();
    for (state.scene.texts.items) |text| {
        state.text_renderer.addLine(text);
    }
    state.text_renderer.updateBuffer();

    const vs_params = state.t.computeVSParams();
    const vs_range = sg.asRange(&vs_params);
    state.pass_action.colors[0] = .{
        .load_action = .CLEAR,
        .clear_value = theme.DARK_THEME.background_color,
    };

    sg.beginPass(.{
        .action = state.pass_action,
        .swapchain = sglue.swapchain(),
    });
    state.dot_grid_renderer.renderInPass(vs_range);
    state.rect_renderer.renderInPass(vs_range);
    state.text_renderer.renderInPass(vs_range);

    sg.endPass();
    sg.commit();
}

export fn cleanup() void {
    state.text_renderer.cleanup();
    state.scene.deinit(state.allocator);
    state.ui.deinit(state.allocator);
    sg.shutdown();

    // Clean up GPA if we created one
    if (state.gpa) |*gpa| {
        const deinit_status = gpa.deinit();
        if (deinit_status == .leak) {
            std.log.err("Memory leak detected!", .{});
        }
    }
}

pub fn main() void {
    sapp.run(.{
        .init_cb = init,
        .frame_cb = frame,
        .cleanup_cb = cleanup,
        .event_cb = input,
        .width = 2 * WIDTH_START,
        .height = 2 * HEIGHT_START,
        .window_title = "tablemd",
        .logger = .{ .func = slog.func },
        .enable_clipboard = true,
        // .sample_count = 4,
        .high_dpi = true,
    });
}

export fn handle_paste_from_web(text_ptr: [*:0]const u8) void {
    const text = std.mem.span(text_ptr);
    if (text.len > 0) {
        state.ui.handlePaste(state.allocator, text) catch |err| {
            std.log.err("Failed to handle paste: {}", .{err});
            return;
        };
        updateTableFromCursorState();
    }
}

/// JS world sends serialized tables to us
export fn handle_deserialize(data_ptr: [*]const u8, data_len: usize) void {
    const data_slice = data_ptr[0..data_len];
    state.ui.deserializeTables(state.allocator, data_slice) catch |err| {
        std.log.err("Failed to deserialize tables: {}", .{err});
        return;
    };
    updateTableFromCursorState();
}

/// JS world requests a serialized version of the current UI
export fn request_serialize() void {
    const serialized_tables = state.ui.serializeTables(state.allocator) catch |err| {
        std.log.err("Failed to serialize tables: {}", .{err});
        return;
    };
    sendSerializedTables(serialized_tables);
}

const PRINT_DOM_STUFF = false;

fn setHtmlRender(html: []const u8) void {
    if (builtin.target.cpu.arch.isWasm()) {
        set_html_render(html.ptr, html.len);
    } else if (PRINT_DOM_STUFF) {
        std.log.info("html:\n{s}", .{html});
    }
}

fn setMarkdownSource(md_src: []const u8) void {
    if (builtin.target.cpu.arch.isWasm()) {
        set_markdown_source(md_src.ptr, md_src.len);
    } else if (PRINT_DOM_STUFF) {
        std.log.info("markdown:\n{s}", .{md_src});
    }
}

fn sendSerializedTables(serialized_tables: []const u8) void {
    if (builtin.target.cpu.arch.isWasm()) {
        set_serialized_tables(serialized_tables.ptr, serialized_tables.len);
    } else if (PRINT_DOM_STUFF) {
        std.log.info("serialized tables:\n{s}", .{serialized_tables});
    }
}

export fn input(ev: ?*const sapp.Event) void {
    const event = ev.?;
    var table_dirty = false;
    switch (event.type) {
        .RESIZED => {
            state.t.updateWindowData(sapp.widthf(), sapp.heightf());
        },
        .MOUSE_MOVE => {
            state.mouse[0] = Vec2{ event.mouse_x, event.mouse_y };
            const point = getPointForUI(state.mouse[0]);
            if (state.mouse_press_pos) |press_pos| {
                const delta_x = state.mouse[0][0] - press_pos[0];
                const delta_y = state.mouse[0][1] - press_pos[1];
                const tolerance_px = 2;
                if (!vec2Equal(.{ delta_x, delta_y }, .{ 0, 0 }, tolerance_px)) {
                    state.is_dragging = true;
                    handlePan(delta_x, delta_y);
                    state.mouse_press_pos = state.mouse[0];
                }
            } else {
                state.ui.handleMouseHover(point);
            }
        },
        .MOUSE_SCROLL => {
            const scroll_x = event.scroll_x;
            const scroll_y = event.scroll_y;
            if ((event.modifiers & sapp.modifier_ctrl) != 0) {
                const zoom_speed = scroll_y * zoomWheelDelta(event);
                handleZoom(zoom_speed, state.mouse[0]);
            } else {
                const pan_speed = 20.0;
                handlePan(scroll_x * pan_speed, scroll_y * pan_speed);
            }
        },
        .MOUSE_DOWN => {
            state.mouse_press_pos = state.mouse[0];
            // Stop any existing momentum when user starts mouse interaction
            state.touch_state.has_momentum = false;
            state.touch_state.velocity = Vec2{ 0, 0 };
        },
        .MOUSE_UP => {
            if (state.mouse_press_pos) |_| {
                if (!state.is_dragging) {
                    const normalized_p = getPointForUI(state.mouse[0]);
                    state.ui.handleMouseClick(normalized_p);
                    table_dirty = true;
                }
                state.mouse_press_pos = null;
                state.is_dragging = false;
            }
        },
        .TOUCHES_BEGAN => {
            handleTouchBegan(event);
        },
        .TOUCHES_MOVED => {
            handleTouchMoved(event);
        },
        .TOUCHES_ENDED => {
            handleTouchEnded(event);
        },
        .TOUCHES_CANCELLED => {
            handleTouchCancelled(event);
        },
        .CHAR => {
            const ctrl_or_cmd = event.modifiers & sapp.modifier_super != 0 or event.modifiers & sapp.modifier_ctrl != 0;
            if (ctrl_or_cmd) {
                if (event.char_code == 'c') {
                    const s = state.ui.handleCopy(state.allocator) catch {
                        std.log.err("Failed to copy text", .{});
                        return;
                    };
                    defer state.allocator.free(s);
                    const null_terminated = std.fmt.allocPrintZ(state.allocator, "{s}", .{s}) catch {
                        return;
                    };
                    defer state.allocator.free(null_terminated);
                    sapp.setClipboardString(null_terminated);
                }
            } else {
                state.ui.handleChar(state.allocator, event.char_code) catch {};
                table_dirty = true;
            }
        },
        .CLIPBOARD_PASTED => {
            const clipboard_text = sapp.getClipboardString();
            if (clipboard_text.len > 0) {
                state.ui.handlePaste(state.allocator, clipboard_text) catch {};
                table_dirty = true;
            }
        },
        .KEY_DOWN => {
            state.ui.handleKeyDown(state.allocator, event.key_code, event.modifiers);
            table_dirty = true;
        },
        else => {},
    }
    if (table_dirty) {
        updateTableFromCursorState();
    }
    // otherwise, leave the current table rendered as-is
}

fn updateTableFromCursorState() void {
    if (state.ui.active_cursor) |cursor| {
        const table: ?*ui.Table = switch (cursor) {
            .empty => null,
            .cell => |cell_pos| state.ui.tables.items[cell_pos.cell_index.table_index],
            .text => |text_pos| state.ui.tables.items[text_pos.cell_index.table_index],
        };
        if (table) |tbl| {
            sendTableToDOM(tbl) catch |err| {
                std.log.err("Failed to send table to DOM: {}", .{err});
            };
        }
    } else {
        clearTableInDOM();
    }
}

fn handlePan(delta_x: f32, delta_y: f32) void {
    const curr_x = state.t.getZoom().x;
    const curr_y = state.t.getZoom().y;
    const new_x = curr_x + delta_x;
    const new_y = curr_y + delta_y;
    state.t.updateZoom(.{ .k = state.t.getZoom().k, .x = new_x, .y = new_y });
}

fn handleZoom(delta: f32, p: Vec2) void {
    const curr_k = state.t.getZoom().k;
    const new_k = clamp(
        curr_k * std.math.pow(f32, 2, delta),
        0.25,
        5.0,
    );
    const inv_p = invert(p);
    const translated = translate(new_k, p, inv_p);
    state.t.updateZoom(.{ .k = new_k, .x = translated[0], .y = translated[1] });
}

/// Unapplies the zoom transform
fn invert(p: Vec2) Vec2 {
    const zoom = state.t.getZoom();
    const x = (p[0] - zoom.x) / zoom.k;
    const y = (p[1] - zoom.y) / zoom.k;
    return Vec2{ x, y };
}

fn translate(k: f32, p0: Vec2, p1: Vec2) Vec2 {
    const x = p0[0] - p1[0] * k;
    const y = p0[1] - p1[1] * k;
    return Vec2{ x, y };
}

fn zoomWheelDelta(event: *const sapp.Event) f32 {
    if ((event.modifiers & sapp.modifier_ctrl) != 0) {
        return 0.25;
    } else {
        return 0.05;
    }
}

fn clamp(x: f32, low: f32, high: f32) f32 {
    return @min(@max(x, low), high);
}

fn vec2Equal(a: Vec2, b: Vec2, tolerance: f32) bool {
    const dx = a[0] - b[0];
    const dy = a[1] - b[1];
    return @abs(dx) <= tolerance and @abs(dy) <= tolerance;
}

fn handleTouchBegan(event: *const sapp.Event) void {
    state.touch_state.active = true;
    state.touch_state.num_touches = @intCast(event.num_touches);

    // Stop any existing momentum when user starts new touch
    state.touch_state.has_momentum = false;
    state.touch_state.velocity = Vec2{ 0, 0 };

    var i: u32 = 0;
    while (i < @as(u32, @intCast(event.num_touches)) and i < 10) : (i += 1) {
        state.touch_state.touches[i] = Vec2{ event.touches[i].pos_x, event.touches[i].pos_y };
        state.touch_state.prev_touches[i] = state.touch_state.touches[i];
    }

    if (state.touch_state.num_touches >= 2) {
        // Initialize pinch gesture
        const dx = state.touch_state.touches[1][0] - state.touch_state.touches[0][0];
        const dy = state.touch_state.touches[1][1] - state.touch_state.touches[0][1];
        state.touch_state.initial_distance = @sqrt(dx * dx + dy * dy);
        state.touch_state.prev_distance = state.touch_state.initial_distance;

        // Calculate center point
        state.touch_state.center = Vec2{
            (state.touch_state.touches[0][0] + state.touch_state.touches[1][0]) * 0.5,
            (state.touch_state.touches[0][1] + state.touch_state.touches[1][1]) * 0.5,
        };
        state.touch_state.prev_center = state.touch_state.center;
    }
}

fn handleTouchMoved(event: *const sapp.Event) void {
    if (!state.touch_state.active) return;

    // Update touch positions
    var i: u32 = 0;
    while (i < @as(u32, @intCast(event.num_touches)) and i < 10) : (i += 1) {
        state.touch_state.prev_touches[i] = state.touch_state.touches[i];
        state.touch_state.touches[i] = Vec2{ event.touches[i].pos_x, event.touches[i].pos_y };
    }

    if (state.touch_state.num_touches == 1) {
        // Single touch - handle as pan/swipe
        const dx = state.touch_state.touches[0][0] - state.touch_state.prev_touches[0][0];
        const dy = state.touch_state.touches[0][1] - state.touch_state.prev_touches[0][1];

        // Track velocity for momentum
        const movement = Vec2{ dx, dy };
        state.touch_state.momentum_samples[state.touch_state.momentum_sample_index] = movement;
        state.touch_state.momentum_sample_index = (state.touch_state.momentum_sample_index + 1) % 5;

        state.is_dragging = true;
        handlePan(dx, dy);
    } else if (state.touch_state.num_touches >= 2) {
        // Multi-touch - handle as pinch and pan
        const dx = state.touch_state.touches[1][0] - state.touch_state.touches[0][0];
        const dy = state.touch_state.touches[1][1] - state.touch_state.touches[0][1];
        const current_distance = @sqrt(dx * dx + dy * dy);

        // Calculate new center
        const current_center = Vec2{
            (state.touch_state.touches[0][0] + state.touch_state.touches[1][0]) * 0.5,
            (state.touch_state.touches[0][1] + state.touch_state.touches[1][1]) * 0.5,
        };

        // Handle pinch zoom
        if (state.touch_state.prev_distance > TOUCH_THRESHOLD) {
            const zoom_distance = current_distance - state.touch_state.prev_distance;
            const factor = 0.002; // from trial and error on what felt "right"
            const zoom_speed = zoom_distance * factor;
            handleZoom(zoom_speed, current_center);
        }

        state.touch_state.prev_distance = current_distance;
        state.touch_state.prev_center = current_center;
    }
}

fn markdownToHtml(md: []const u8) ![]const u8 {
    // convert markdown to html
    var parser = try markdown.Parser.init(state.allocator);
    defer parser.deinit();
    var lines = std.mem.splitScalar(u8, md, '\n');
    while (lines.next()) |line| {
        try parser.feedLine(line);
    }
    var doc = try parser.endInput();
    defer doc.deinit(state.allocator);

    var html_str = std.ArrayList(u8).init(state.allocator);
    defer html_str.deinit();
    try doc.render(html_str.writer());
    return html_str.toOwnedSlice();
}

fn handleTouchEnded(event: *const sapp.Event) void {
    const prev_num_touches = state.touch_state.num_touches;
    state.touch_state.num_touches = @intCast(event.num_touches);

    if (!state.is_dragging and prev_num_touches == 1 and state.touch_state.num_touches == 1) {
        const final_pos = Vec2{ event.touches[0].pos_x, event.touches[0].pos_y };
        const normalized_p = getPointForUI(final_pos);
        state.ui.handleMouseClick(normalized_p);
        activateMobileKeyboard();
    }

    // Calculate momentum if we were dragging
    if (state.is_dragging) {
        // Average the last few movement samples for smooth momentum
        var avg_velocity = Vec2{ 0, 0 };
        var sample_count: f32 = 0;

        for (state.touch_state.momentum_samples) |sample| {
            if (sample[0] != 0 or sample[1] != 0) {
                avg_velocity[0] += sample[0];
                avg_velocity[1] += sample[1];
                sample_count += 1;
            }
        }

        if (sample_count > 0) {
            avg_velocity[0] /= sample_count;
            avg_velocity[1] /= sample_count;

            // Scale and clamp momentum
            const speed = @sqrt(avg_velocity[0] * avg_velocity[0] + avg_velocity[1] * avg_velocity[1]);
            if (speed > MOMENTUM_MIN_SPEED) {
                const scale = @min(MOMENTUM_MAX_SPEED / speed, 3.0); // Boost momentum but cap it
                state.touch_state.velocity = Vec2{ avg_velocity[0] * scale, avg_velocity[1] * scale };
                state.touch_state.has_momentum = true;
            }
        }

        // Clear momentum samples
        state.touch_state.momentum_samples = [_]Vec2{Vec2{ 0, 0 }} ** 5;
        state.touch_state.momentum_sample_index = 0;
    }

    state.is_dragging = false;
    if (state.touch_state.num_touches == 0) {
        state.touch_state.active = false;
        state.touch_state.initial_distance = 0;
        state.touch_state.prev_distance = 0;
    } else if (state.touch_state.num_touches == 1) {
        // Reset pinch state when going from multi-touch to single touch
        state.touch_state.initial_distance = 0;
        state.touch_state.prev_distance = 0;
    }
}

fn handleTouchCancelled(event: *const sapp.Event) void {
    _ = event;
    state.touch_state.active = false;
    state.touch_state.num_touches = 0;
    state.touch_state.initial_distance = 0;
    state.touch_state.prev_distance = 0;
}

fn clear() void {
    state.rect_renderer.clear();
    state.text_renderer.clear();
    state.scene.clear();
}

fn normalizePt(p: Vec2) Vec2 {
    const w = sapp.widthf();
    const h = sapp.heightf();
    const min_dim = @min(w, h);
    const grid_x = p[0] / min_dim;
    const grid_y = p[1] / min_dim;
    return Vec2{ grid_x, grid_y };
}

/// Returns a normalized vec2 from a mouse position.
/// Used to feed into the UI.
fn getPointForUI(mouse_p: Vec2) Vec2 {
    const inv_p = invert(mouse_p);
    const normalized_p = normalizePt(inv_p);
    return normalized_p;
}

fn sendTableToDOM(table: *ui.Table) !void {
    const table_as_md = try table.md(state.allocator);
    defer state.allocator.free(table_as_md);
    setMarkdownSource(table_as_md);

    // convert markdown to html
    const html_str = try markdownToHtml(table_as_md);
    defer state.allocator.free(html_str);
    setHtmlRender(html_str);
}

fn clearTableInDOM() void {
    setMarkdownSource("");
    setHtmlRender("");
}

fn activateMobileKeyboard() void {
    if (builtin.target.cpu.arch.isWasm()) {
        activate_mobile_keyboard();
    }
}
