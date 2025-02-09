
const std = @import("std");
const log = std.log;

const zgl = @import("zgl");
const glfw = zgl.glfw;
const wgpu = zgl.wgpu;

const shader_code = @embedFile("shader.wgsl");

const assert = std.debug.assert;


const ASPECT_RATIO: f32 = 16.0 / 9.0;

const WINDOW_WIDTH = 1080;
const WINDOW_HEIGHT = @divTrunc(WINDOW_WIDTH, ASPECT_RATIO);

// Packed: Fields remain in the order declared, least to most significant.
const Position = struct { x: f32, y: f32, z: f32 };

const ViewPort = struct {
    width: f32,
    height: f32,
};

const Camera = struct {
    center: struct { x: f32, y: f32, z: f32},
    focal_length: f32,
    view_port: ViewPort,
    samples_per_pixel: u32,
    max_depth: u32,
};


const Material = enum(u32) {
    Lambertian = 0,
    Metal = 1,
    Dielectric = 2,
};

const Sphere = struct {
    center: Position,
    radius: f32,
    material: Material = .Lambertian,
    color: struct { r: f32, g: f32, b: f32 } = .{ .r = 0, .g = 0, .b = 0},
    metal_fuzz: f32 = 0,
    refraction_index: f32 = 0
};

pub fn main() !void {
    const v_height = 2.0;
    const v_width = v_height * WINDOW_WIDTH / WINDOW_HEIGHT;

    const camera = Camera {
        .center = .{ .x = 0, .y = 0, .z = 0 },
        .focal_length = 1,
        .view_port = .{ 
            .width = v_width, 
            .height = v_height 
        },
        .samples_per_pixel = 5,
        .max_depth = 10
    };

    try glfw.init();
    defer glfw.terminate();

    glfw.Window.hint(.{ .resizable = false, .client_api = .NO_API });
    log.debug("aspect ratio = {}", .{ASPECT_RATIO});
    log.debug("window: width = {}, height = {}", .{WINDOW_WIDTH, WINDOW_HEIGHT});
    log.debug("viewport: width = {}, height = {}", .{
        camera.view_port.width, camera.view_port.height
    });
    const window = try glfw.Window.Create(WINDOW_WIDTH, WINDOW_HEIGHT, "Raytracing!");
    defer  window.destroy();


    const instance = try wgpu.CreateInstance(null);
    defer instance.release();

    const surface = try glfw.GetWGPUSurface(window, instance);
    defer surface.release();

    const adapter = try instance.RequestAdapter(null);
    defer adapter.release();

    const device = try adapter.RequestDevice(null);
    defer device.release();

    //const format = wgpu.TextureFormat.BGRA8Unorm;
    const format = surface.GetPreferredFormat(adapter);
    log.debug("using format: {s}", .{@tagName(format)});
    const surface_conf = wgpu.SurfaceConfiguration {
        .device = device,
        .format = format,
        .width = WINDOW_WIDTH,
        .height = WINDOW_HEIGHT,
        .usage = .RenderAttachment,
        .presentMode = .Immediate,
    };

    surface.configure(&surface_conf);
    defer surface.unconfigure();

    const queue = try device.GetQueue();
    defer queue.release();

    const wgsl_code = wgpu.ShaderSourceWGSL {
        .code = .fromSlice(shader_code),
        .chain = .{ .next = null, .sType = .ShaderSourceWGSL }
    };

    const shader_module = try device.CreateShaderModule(&.{
        .label = .fromSlice("shader module"),
        .nextInChain = &wgsl_code.chain
    });
    defer shader_module.release();

    const render_pipeline = try device.CreateRenderPipeline(&wgpu.RenderPipelineDescriptor {
        .vertex = .{
            .module = shader_module,
            .entryPoint = "vs_main",
            .buffers = &.{
                wgpu.VertexBufferLayout {
                    .stepMode = .Vertex,
                    .arrayStride = 2 * @sizeOf(f32),
                    .attributeCount = 1,
                    .attributes = &[1]wgpu.VertextAttribute {
                        wgpu.VertextAttribute {
                            .format = .Float32x2,
                            .offset = 0,
                            .shaderLocation = 0
                        }
                    }
                    
                }
            }
        },
        .primitive = .{
            .topology = .TriangleList,
            .stripIndexFormat = .Undefined,
            .frontFace = .CCW, //counter clockwise
            .cullMode = .None,
            .unclippedDepth = false
        },
        .fragment = &wgpu.FragmentState{
            .module = shader_module,
            .entryPoint = wgpu.StringView.fromSlice("fs_main"),
            .targetCount = 1,
            .targets = &[1]wgpu.ColorTargetState {
                .{
                    .format = surface_conf.format,
                    .blend = &wgpu.BlendState {
                        .color = .{
                            .srcFactor = .SrcAlpha,
                            .dstFactor = .OneMinusSrcAlpha,
                            .operation = .Add,
                        },
                        .alpha = .{
                            .srcFactor = .Zero,
                            .dstFactor = .One,
                            .operation = .Add
                        }
                    },
                    .writeMask = .All
                }
            }
        },
        .multisample = .{
            .count = 1,
            .mask = ~@as(u32, 0),
            .alphaToCoverageEnabled = false
        },
    });
    defer render_pipeline.Release();

    const vertex_data = [_]f32 {
        // x, y - first triangle
        -1,  1, // top left
        -1, -1, // bottom left
         1,  1, // top right

         1,  1, // top right
         1, -1, // bottom right 
        -1, -1, // bottom left
    };

    const vertex_buffer = try device.CreateBuffer(&.{
        .label = .fromSlice("vertex buffer"),
        .usage = @intFromEnum(wgpu.BufferUsage.Vertex) | @intFromEnum(wgpu.BufferUsage.CopyDst),
        .size = @sizeOf(@TypeOf(vertex_data)),
    });
    defer vertex_buffer.release();

    queue.WriteBuffer(vertex_buffer, 0, f32, &vertex_data);

    const window_uniform_buffer = try device.CreateBuffer(&.{
        .label = .fromSlice("window size"),
        .usage = @intFromEnum(wgpu.BufferUsage.Uniform) | @intFromEnum(wgpu.BufferUsage.CopyDst),
        .size = 2 * @sizeOf(f32),
    });
    defer window_uniform_buffer.release();

    queue.WriteBuffer(window_uniform_buffer, 0, f32, &.{ WINDOW_WIDTH, WINDOW_HEIGHT });

    const camera_uniform_buffer = try device.CreateBuffer(&.{
        .label = .fromSlice("camera"),
        .usage = @intFromEnum(wgpu.BufferUsage.Uniform) | @intFromEnum(wgpu.BufferUsage.CopyDst),
        .size = @sizeOf(Camera),
    });
    defer camera_uniform_buffer.release();

    queue.WriteBuffer(camera_uniform_buffer, 0, Camera, &.{ camera });
    

    const spheres_data = [_]Sphere {
        Sphere {
            .center = .{ .x = 0, .y = -100.5, .z = -1},
            .radius = 100,
            .color = .{ .r = 0.8, .g = 0.8, .b = 0.0 }
        },
        Sphere { 
            .center = .{ .x = 0, .y = 0, .z = -1.2 }, 
            .radius = 0.5,
            .color = .{ .r = 0.1, .g = 0.2, .b = 0.5}
        },
        Sphere {
            .center = .{ .x = -1, .y = 0, .z = -1},
            .radius = 0.5,
            .material = .Dielectric,
            .refraction_index = 1.0 / 1.33
        },
        Sphere {
            .center = .{ .x = 1, .y = 0, .z = -1},
            .radius = 0.5,
            .material = .Metal,
            .color = .{ .r = 0.8, .g = 0.6, .b = 0.2 },
            .metal_fuzz = 1
        }
    };

    const spheres_buffer = try device.CreateBuffer(&.{
        .label = .fromSlice("spheres"),
        .usage = @intFromEnum(wgpu.BufferUsage.Storage) | @intFromEnum(wgpu.BufferUsage.CopyDst),
        .size = @sizeOf(Sphere) * spheres_data.len,
    });
    defer spheres_buffer.release();
    

    log.debug("position size = {}", .{@sizeOf(Position)});

    //assert(@sizeOf(@TypeOf(spheres_data)) == spheres_buffer.getSize());
    log.debug("using bitsize = {} bytes", .{@bitSizeOf(Sphere) * spheres_data.len / 8});

    log.debug("alignment of Sphere = {}", .{@alignOf(Sphere)});
    log.debug("alignment of spheres = {}", .{@alignOf(@TypeOf(spheres_data))});
    log.debug("Size of one Sphere is {} bytes", .{@sizeOf(Sphere)});
    log.debug("spheres_buffer size = {}", .{spheres_buffer.getSize()});

    queue.WriteBuffer(spheres_buffer, 0, Sphere, &spheres_data);

    const sphere_len_buffer =  try device.CreateBuffer(&.{
        .label = .fromSlice("sphere len"),
        .usage = @intFromEnum(wgpu.BufferUsage.Uniform) | @intFromEnum(wgpu.BufferUsage.CopyDst),
        .size = @sizeOf(u32),
    });
    defer sphere_len_buffer.release();

    assert(@sizeOf(u32) == sphere_len_buffer.getSize());

    queue.WriteBuffer(sphere_len_buffer, 0, u32, &.{ @intCast(spheres_data.len) });

    log.debug("sphere_len_buffer size = {}", .{sphere_len_buffer.getSize()});

    const bind_group = try device.CreateBindGroup(&.{
        .label = .fromSlice("bind group"),
        .layout = try render_pipeline.GetBindGroupLayout(0),
        .entryCount = 4,
        .entries = &[4]wgpu.BindGroupEntry {
            wgpu.BindGroupEntry {
                .binding = 0,
                .offset = 0,
                .size = window_uniform_buffer.getSize(),
                .buffer = window_uniform_buffer
            },

            wgpu.BindGroupEntry {
                .binding = 1,
                .offset = 0,
                .size = camera_uniform_buffer.getSize(),
                .buffer = camera_uniform_buffer
            },
            wgpu.BindGroupEntry {
                .binding = 2,
                .offset = 0,
                .size = spheres_buffer.getSize(),
                .buffer = spheres_buffer
            },

            wgpu.BindGroupEntry {
                .binding = 3,
                .offset = 0,
                .size = sphere_len_buffer.getSize(),
                .buffer = sphere_len_buffer
            },
        }
    });
    defer bind_group.release();


    while (!window.ShouldClose()) {

        glfw.pollEvents();

        const texture = try surface.GetCurrentTexture();
        defer texture.release();

        const view = try texture.CreateView(&.{
            .format = surface_conf.format,
            .dimension = .@"2D",
            .baseMipLevel = 0,
            .mipLevelCount = 1,
            .baseArrayLayer = 0,
            .arrayLayerCount = 1,
            .aspect = .All,
            .usage = .RenderAttachment
        });
        defer view.release();

        const command_encoder = try device.CreateCommandEncoder(&.{});
        defer command_encoder.release();
        
        {

            const rend_pass_enc = try command_encoder.BeginRenderPass(&.{
                .colorAttachmentCount = 1,
                .colorAttachments = &[1]wgpu.RenderPassColorAttachment{
                    wgpu.RenderPassColorAttachment {
                        .view = view,
                        .loadOp = .Clear,
                        .storeOp = .Store,
                        .clearValue = .{ .r = 0, .g = 0, .b = 0, .a = 1 },
                    }
                }
            });
            defer rend_pass_enc.release();

            rend_pass_enc.setPipeline(render_pipeline);
            rend_pass_enc.setVertexBuffer(0, vertex_buffer, 0);
            rend_pass_enc.setBindGroup(0, bind_group, &.{});
            rend_pass_enc.draw(vertex_data.len / 2, 1, 0, 0);
            rend_pass_enc.end();

        }


        const command_buffer = try command_encoder.finish(&.{});
        defer command_buffer.release();

        queue.submit(&.{ command_buffer });

        surface.present();
        _ = device.poll(false, null);

    }



}

