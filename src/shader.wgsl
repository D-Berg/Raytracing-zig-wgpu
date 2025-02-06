
struct VertexIn {
    @location(0) position: vec2f,
}

struct VertexOut {
    @builtin(position) position: vec4f,
}

@vertex
fn vs_main(in: VertexIn) -> VertexOut {

    var VertexOut: VertexOut;
    VertexOut.position = vec4f(in.position, 0, 1);

    return VertexOut;

}

@fragment
fn fs_main(in: VertexOut) -> @location(0) vec4f {

    return vec4f(1, 0, 0, 1);

}




