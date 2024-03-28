#!/bin/bash
mkdir -p server/build
zig build-lib core/src/lib.zig -target wasm32-freestanding -OReleaseSmall -femit-bin=server/build/core.o
wasm-ld server/build/core.o -o server/build/core.wasm -O2 --no-entry --allow-undefined
