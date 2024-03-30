#!/bin/bash
mkdir -p web/build
zig build-lib core/src/lib.zig -target wasm32-freestanding -fno-entry -rdynamic -fallow-shlib-undefined -femit-bin=web/build/core.wasm $1 $2 $3
wasm-ld --no-entry --export-dynamic --export-all --allow-undefined --import-memory -o web/build/core.wasm web/build/core.wasm.o
