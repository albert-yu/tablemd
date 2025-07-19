mergeInto(LibraryManager.library, {
    console_log: function(ptr, len) {
        const message = UTF8ToString(ptr, len);
        console.log("[Zig]: " + message);
    }
});
