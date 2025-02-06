
@group(0) @binding(0) var<uniform> window_size: vec2f;

struct VertexIn {
    @location(0) position: vec2f,
}

struct VertexOut {
    @builtin(position) position: vec4f,
    @location(0) window_size: vec2f,
}

@vertex
fn vs_main(in: VertexIn) -> VertexOut {

    var out: VertexOut;
    out.position = vec4f(in.position, 0, 1);
    out.window_size = window_size;

    return out;

}

@fragment
fn fs_main(in: VertexOut) -> @location(0) vec4f {

    return vec4f(in.position.xy / window_size, 0, 1);

}




