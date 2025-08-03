// Stub implementation of setjmp/longjmp for WebAssembly
// This provides the missing symbols that FreeType needs but doesn't actually implement
// the full setjmp/longjmp functionality since it's not supported in WASM

#include <stdint.h>

// Simple stub implementation that always returns 0
// In a real implementation, setjmp would save the execution context
// and longjmp would restore it, but for our use case we'll just
// provide the symbols to satisfy the linker
int setjmp(void* env) {
    (void)env; // Suppress unused parameter warning
    return 0;
}

// Stub longjmp that does nothing
// In a real implementation this would restore the execution context
// saved by setjmp and jump back to it
void longjmp(void* env, int val) {
    (void)env; // Suppress unused parameter warning
    (void)val; // Suppress unused parameter warning
    // In a real WASM environment, we might want to throw an exception
    // or call abort() here, but for now we'll just return
}