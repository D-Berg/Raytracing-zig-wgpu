
// struct VertexIn {}

struct VertexOut {
    @builtin(position) position: vec4f,
}

@vertex
fn vs_main() -> VertexOut {

    var VertexOut: VertexOut;
    VertexOut.position = vec4f(1, 1, 1, 1);

    return VertexOut;

}

@fragment
fn fs_main(in: VertexOut) -> @location(0) vec4f {

    return in.position;

}




