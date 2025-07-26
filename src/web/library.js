// Note: emscripten functions (e.g. UTF8ToString) here
// do not need the Module. prefix
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
        const buffer = new Uint8Array(HEAPU8.buffer, ptr, len);
        // Copy the buffer since it might be invalidated
        const data = new Uint8Array(buffer);

        // Write to IndexedDB
        const request = indexedDB.open('tablemd', 1);

        request.onupgradeneeded = function(event) {
            const db = event.target.result;
            if (!db.objectStoreNames.contains('tables')) {
                db.createObjectStore('tables');
            }
        };

        request.onsuccess = function(event) {
            const db = event.target.result;
            const transaction = db.transaction(['tables'], 'readwrite');
            const store = transaction.objectStore('tables');

            store.put(data, 'current_tables').onsuccess = function() {
                console.log('Tables saved to IndexedDB');
            };

            transaction.onerror = function() {
                console.error('Failed to save tables to IndexedDB');
            };
        };

        request.onerror = function() {
            console.error('Failed to open IndexedDB');
        };
    },
});
