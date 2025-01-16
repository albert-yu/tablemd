/**
 * Just a pointer
 */
export type WASMApp = number;

export type WASMExports = WebAssembly.Exports & {
  app_init: (
    canvas_width: number,
    canvas_height: number,
    sheet_count: number,
  ) => WASMApp;
  app_deinit: (app: WASMApp) => void;
  app_set_canvas_size: (app: WASMApp, width: number, height: number) => void;
  app_on_hover: (app: WASMApp, x: number, y: number) => void;
  app_write_hover_rect: (
    app: WASMApp,
    float_array: Float32Array,
    offset: number,
  ) => void;
};
