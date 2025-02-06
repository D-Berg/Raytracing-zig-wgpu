
@group(0) @binding(0) var<uniform> window_size: vec2f;
@group(0) @binding(1) var<uniform> camera: Camera;

struct Camera {
    center: vec3f,
    focal_length: f32,
    view_port: vec2f
}

struct VertexIn {
    @location(0) position: vec2f,
}

struct VertexOut {
    @builtin(position) position: vec4f,
}

struct Ray {
    orig: vec3f,
    dir: vec3f
}

fn getRayColor(ray: Ray) -> vec3f {

    let unit_dir = normalize(ray.dir);

    let a = 0.5 * (unit_dir.y + 1.0);
    return (1.0 - a) * vec3f(1.0, 1.0, 1.0) + a * vec3f(0.5, 0.7, 1.0);

}

@vertex
fn vs_main(in: VertexIn) -> VertexOut {

    var out: VertexOut;
    out.position = vec4f(in.position, 0, 1);

    return out;

}

@fragment
fn fs_main(in: VertexOut) -> @location(0) vec4f {

    let viewport_u = vec3(camera.view_port.x, 0, 0);
    let viewport_v = vec3(0, -camera.view_port.y, 0);
    
    let pixel_delta_u = viewport_u / window_size.x;
    let pixel_delta_v = viewport_v / window_size.y;

    let view_port_upper_left = camera.center - vec3f(0, 0, camera.focal_length) 
        - viewport_u / 2.0 - viewport_v / 2.0;

    let pixel_00_loc = view_port_upper_left + 0.5  * (pixel_delta_u + pixel_delta_v);

    let pixel_center = pixel_00_loc 
        + in.position.x * pixel_delta_u 
        + in.position.y * pixel_delta_v;

    var ray: Ray;
    ray.orig = camera.center;
    ray.dir = pixel_center - camera.center;

    let color = getRayColor(ray);

    return vec4f(color, 1);

}




