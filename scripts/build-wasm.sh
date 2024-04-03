#!/bin/bash
mkdir -p web/build
zig build-exe core/src/lib.zig -target wasm32-freestanding -fno-entry -rdynamic -femit-bin=web/build/core.wasm $1 $2 $3
du -sh web/build/core.wasm
