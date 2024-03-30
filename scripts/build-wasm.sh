#!/bin/bash
mkdir -p web/build
zig build-exe core/src/lib.zig -target wasm32-freestanding -fno-entry -rdynamic --import-symbols --import-memory -femit-bin=web/build/core.wasm $1 $2 $3
