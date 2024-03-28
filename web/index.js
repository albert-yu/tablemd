try {
  const response = await fetch("build/core.wasm");
  const bytes = await response.arrayBuffer();
  const result = await WebAssembly.instantiate(bytes, {
    env: {
      print: (result) => console.log(result),
    },
  });
  const newSheet = result.instance.exports.newSheet;
  newSheet();
} catch (err) {
  console.log(err);
}
