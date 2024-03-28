#!/bin/bash
mkdir -p server/build
zig build-exe core/src/lib.zig -target wasm32-freestanding -fno-entry --export=newSheet -femit-bin=server/build/core.wasm
