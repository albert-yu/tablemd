const math = @import("math.zig");
const Mat4 = math.Mat4;

const Interval = struct {
    low: f32,
    high: f32,
};

const ScaleDomainAndRange = struct {
    domain: Interval,
    range: Interval,
};

const Scales = struct {
    x: ScaleDomainAndRange,
    y: ScaleDomainAndRange,
};

pub const Zoom = struct {
    k: f32,
    x: f32,
    y: f32,
};

pub const Transform = struct {
    zoom: Mat4,
    window_scale: Mat4,
    untransform: Mat4,

    pub fn new() Transform {
        return Transform{
            .zoom = Mat4.identity(),
            .window_scale = Mat4.identity(),
            .untransform = Mat4.identity(),
        };
    }

    pub fn updateZoom(self: *Transform, zoom: Zoom) void {
        // m = [4][4]f32{
        //     .{ k, 0.0, 0.0, 0.0 },
        //     .{ 0.0, k, 0.0, 0.0 },
        //     .{ 0.0, 0.0, 1.0, 0.0 },
        //     .{ x, y, 0.0, 1.0 },
        // };
        self.zoom.m[0][0] = zoom.k;
        self.zoom.m[1][1] = zoom.k;
        self.zoom.m[3][0] = zoom.x;
        self.zoom.m[3][1] = zoom.y;
    }

    pub fn getZoom(self: Transform) Zoom {
        return Zoom{
            .k = self.zoom.m[0][0],
            .x = self.zoom.m[3][0],
            .y = self.zoom.m[3][1],
        };
    }

    pub fn updateWindowData(self: *Transform, w: f32, h: f32) void {
        const range = if (w < h) w else h;
        const scales: Scales = .{
            .x = .{
                .domain = .{ .low = 0, .high = 1 },
                .range = .{ .low = 0, .high = range },
            },
            .y = .{
                .domain = .{ .low = 0, .high = 1 },
                .range = .{ .low = 0, .high = range },
            },
        };
        const matrices = windowTransform(scales, w, h);
        self.window_scale = matrices[0];
        self.untransform = matrices[1];
    }
};

fn windowTransform(scales: Scales, width: f32, height: f32) struct { Mat4, Mat4 } {
    const x_domain = scales.x.domain;
    const y_domain = scales.y.domain;
    const x_range = scales.x.range;
    const y_range = scales.y.range;

    const x_domain_mid = mean(x_domain);
    const y_domain_mid = mean(y_domain);
    const x_range_mid = mean(x_range);
    const y_range_mid = mean(y_range);

    const xmulti = gap(x_range) / gap(x_domain);
    const ymulti = gap(y_range) / gap(y_domain);

    // translates from data space to scaled space
    var m1 = Mat4.zero();
    m1.m = [4][4]f32{
        .{ xmulti, 0.0, 0.0, 0.0 },
        .{ 0.0, ymulti, 0.0, 0.0 },
        .{ 0.0, 0.0, 1.0, 0.0 },
        .{ -xmulti * x_domain_mid + x_range_mid, -ymulti * y_domain_mid + y_range_mid, 0.0, 1.0 },
    };

    // translate from scaled space to webgl space
    var m2 = Mat4.zero();
    m2.m = [4][4]f32{
        .{ 2.0 / width, 0.0, 0.0, 0.0 },
        .{ 0.0, -2.0 / height, 0.0, 0.0 },
        .{ 0.0, 0.0, 1.0, 0.0 },
        .{ -1.0, 1.0, 0.0, 1.0 },
    };

    return .{ m1, m2 };
}

fn mean(interval: Interval) f32 {
    return (interval.high - interval.low) / 2.0;
}

fn gap(interval: Interval) f32 {
    return interval.high - interval.low;
}
