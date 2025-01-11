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
};
