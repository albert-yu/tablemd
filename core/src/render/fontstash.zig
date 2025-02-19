const c = @cImport({
    @cInclude("fontstash.h");
});

pub const Context = c.FONScontext;

pub fn create(width: i32, height: i32) ?*Context {
    var params: c.FONSparams = .{
        .width = width,
        .height = height,
        // ... other params
    };
    return c.fonsCreateInternal(&params);
}
