
const std = @import("std");

const zgl = @import("zgl");
const glfw = zgl.glfw;
const wgpu = zgl.wgpu;

const WINDOW_WIDTH = 600;
const WINDOW_HEIGHT = 600;

pub fn main() !void {

    try glfw.init();
    defer glfw.terminate();

    glfw.Window.hint(.{ .resizable = false, .client_api = .NO_API });
    const window = try glfw.Window.Create(WINDOW_WIDTH, WINDOW_HEIGHT, "Raytracing!");
    defer  window.destroy();


    while (!window.ShouldClose()) {

        glfw.pollEvents();

    }




}

