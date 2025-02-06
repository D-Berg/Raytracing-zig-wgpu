
const std = @import("std");

const zgl = @import("zgl");
const glfw = zgl.glfw;
const wgpu = zgl.wgpu;

const shader_code = @embedFile("shader.wgsl");

const WINDOW_WIDTH = 600;
const WINDOW_HEIGHT = 600;

pub fn main() !void {

    try glfw.init();
    defer glfw.terminate();

    glfw.Window.hint(.{ .resizable = false, .client_api = .NO_API });
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

    const surface_conf = wgpu.SurfaceConfiguration {
        .device = device,
        .format = surface.GetPreferredFormat(adapter),
        .width = WINDOW_WIDTH,
        .height = WINDOW_HEIGHT,
        .usage = .RenderAttachment,
        .presentMode = .Fifo,
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
            rend_pass_enc.end();

        }


        const command_buffer = try command_encoder.finish(&.{});
        defer command_buffer.release();

        queue.submit(&.{ command_buffer });

        surface.present();
        _ = device.poll(false, null);

    }



}

