#!/bin/bash
mkdir -p build
zig build-lib core/src/lib.zig -target wasm32-freestanding -fno-entry --export=newSheet -femit-bin=build/core.wasm
