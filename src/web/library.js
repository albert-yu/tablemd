mergeInto(LibraryManager.library, {
    set_html_render: function(ptr, len) {
        const html = UTF8ToString(ptr, len);
        const renderElement = document.getElementById("html-render");
        if (renderElement) {
            renderElement.innerHTML = html;
        }
    },
    set_markdown_source: function(ptr, len) {
        const markdown = UTF8ToString(ptr, len);
        const markdownElement = document.getElementById("markdown-source");
        if (markdownElement) {
            markdownElement.innerHTML = markdown;
        }
    },
    activate_mobile_keyboard: function() {
        const input = document.querySelector('#mobile-keyboard-focus');
        // Focus the input to show the keyboard
        input?.focus();
    },
    set_serialized_tables: function(ptr, len) {
        const buffer = new Uint8Array(Module.HEAPU8.buffer, ptr, len);
        console.log('got buffer', buffer);
    },
});
