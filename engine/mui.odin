package engine 

import mu "vendor:microui"
import sdl "vendor:sdl2"
import vk "vendor:vulkan"

import "vendor:sdl2/ttf"
import "core:fmt"
import "core:strings"

import "core:math/linalg"
import "core:math"

UI :: struct {
    id: i32,
    pos: Vec3,
    size: Vec2,
    color: Vec4,
    vertex: ^Buffer,
    indices: ^Buffer
}

UIVertex :: struct {
    pos:     Vec2,   
    uv:      Vec2,   
    color:   Vec4,   
}

screenToNDC :: proc(pos: Vec3, size: Vec2, swapchain: Swapchain) -> linalg.Matrix4f32{
    h := f32(swapchain.extent.height)
    w := f32(swapchain.extent.width)


    scaleX := size.x / w 
    scaleY := size.y / h
    ndcX := (pos.x / w) * 2.0 - 1.0 + scaleX
    ndcY := 1.0 - (pos.y / h) * 2.0 - scaleY
    translated := linalg.matrix4_translate_f32(Vec3{ndcX, ndcY, pos.z})
    scaled := linalg.matrix4_scale_f32(Vec3{scaleX, scaleY, 1.0})

    return linalg.mul(translated, scaled)
}

AddUI :: proc(ctx: ^Context) {

    uiRect := UIRect()
    color := uiRect[0].color
    vBuffer := createVertexBuffer(ctx, uiRect[:])
    iBuffer := createIndexBuffer(ctx, []u32{0, 1, 2, 2, 1, 3})

    append(&ctx.ui.elements, UI{
        5, Vec3{50, 50, 1}, Vec2{50, 50}, color, vBuffer, iBuffer 
    })
}

UIRect :: proc() -> [4]UIVertex {
    return [4]UIVertex{
        {Vec2{0, 0}, Vec2{0, 0}, Vec4{55, 0, 0, 1}},
        {Vec2{1, 0}, Vec2{1, 0}, Vec4{55, 0, 0, 1}},
        {Vec2{0, 1}, Vec2{0, 1}, Vec4{55, 0, 0, 1}},
        {Vec2{1, 1}, Vec2{1, 1}, Vec4{55, 0, 0, 1}},
    }
}

UI_VERTEX_BINDING := vk.VertexInputBindingDescription{
    binding = 0,
    stride = size_of(UIVertex),
    inputRate = .VERTEX,
}

UI_VERTEX_ATTRIBUTES := [3]vk.VertexInputAttributeDescription{
    {
        binding = 0,
        location = 0,                      // matches ui.vert: layout(location = 0) in vec3 inPos
        format = .R32G32_SFLOAT,           // vec2
        offset = cast(u32)offset_of(UIVertex, pos),
    },
    {
        binding = 0,
        location = 1,                      // matches ui.vert: layout(location = 1) in vec2 inUV
        format = .R32G32_SFLOAT,           // vec2
        offset = cast(u32)offset_of(UIVertex, uv),
    },
    {
        binding = 0,
        location = 2,                      // matches ui.vert: layout(location = 2) in vec4 inColor
        format = .R32G32B32A32_SFLOAT,     // vec4
        offset = cast(u32)offset_of(UIVertex, color),
    },
}

