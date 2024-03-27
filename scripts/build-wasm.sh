#!/bin/bash
mkdir -p server/build
zig build-lib core/src/lib.zig -target wasm32-freestanding -fno-entry --export=newSheet -femit-bin=server/build/core.wasm
