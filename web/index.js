let currentStr = "";

try {
  const response = await fetch("build/core.wasm");
  const bytes = await response.arrayBuffer();
  const result = await WebAssembly.instantiate(bytes, {
    env: {
      print_char: (s) => {
        if (s === 0) {
          // sentinel value, terminate
          console.log(currentStr);
        } else {
          const char = String.fromCharCode(s);
          currentStr += char;
        }
      },
    },
  });
  const exports = result.instance.exports;
  const newSheet = exports.newSheet;
  const freeSheet = exports.freeSheet;
  const v = newSheet();
  console.log("v", v);
  // const memory = result.instance.exports.memory;
  freeSheet(v);
} catch (err) {
  console.log(err);
}
