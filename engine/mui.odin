package engine 

import mu "vendor:microui"
import sdl "vendor:sdl2"
import vk "vendor:vulkan"

import "vendor:sdl2/ttf"
import "core:fmt"
import "core:strings"

import "core:math/linalg"
import "core:math"

UIElement :: struct {  
    id: i32,
    pos: Vec3,
    size: Vec2,
    color: Vec3,
    vertex_buffer: ^Buffer,
    text: string,
    stagedText: string,
}

debug_vertices :: proc(vertices: []TextVertex, text: string) {    
    if len(vertices) > 0 {
        
        min_x, max_x, min_y, max_y: f32 = f32(max(f32)), -f32(max(f32)), f32(max(f32)), -f32(max(f32))
        for v in vertices {
            min_x = min(min_x, v.pos.x)
            max_x = max(max_x, v.pos.x)
            min_y = min(min_y, v.pos.y)
            max_y = max(max_y, v.pos.y)
        }
        fmt.printf("Bounds: x[%.1f, %.1f] y[%.1f, %.1f]\n", min_x, max_x, min_y, max_y)
    }
}

debug_glyph_tex_coords :: proc(font: ^Font) {
    for ch in 'A'..<'F' {
        glyph := font.glyphs[ch]
}

UpdateUI :: proc(ctx: ^Context) {
    using ctx.ui
    using ctx.vulkan

    for &element, i in elements {
        if element.text != element.stagedText {
            destroyBuffer("elementVBuffer", device, element.vertex_buffer^)
            vertices := render_text(ctx, &font, element.stagedText, 100, 100, {1, 0.66, 0.11})
            defer delete(vertices)

            vertex_buffer := createVertexBuffer(ctx, vertices[:])
            element.vertex_buffer = vertex_buffer
            element.text = element.stagedText
        }
    }
}

AddUI :: proc(ctx: ^Context) -> bool {
    font, font_ok := createFontFromFile(ctx, "Roboto-Regular", 32.0, "arial")
    ctx.ui.font = font

    if !font_ok {
        fmt.eprintln("Failed to load font")
        return false
    }
    text := ctx.scene.isPlayer ? "Playing" : "Viewing"
    vertices := render_text(ctx, &font, text, 100, 100, {1, 0.66, 0.11})
    defer delete(vertices)


    if len(vertices) == 0 {
        fmt.eprintln("No vertices generated for text")
        return false
    }

    vertex_buffer := createVertexBuffer(ctx, vertices[:])
    if vertex_buffer.buffer == 0 {
        fmt.eprintln("Failed to create vertex buffer")
        return false
    }

    uie1 := UIElement{
        id = 1,
        pos = {100, 100, 0},
        size = {100, 100}, 
        color = {1, 1, 1},
        vertex_buffer = vertex_buffer,
        text = text,
        stagedText = text
    }


    append(&ctx.ui.elements, uie1)
    fmt.printf("Created UI element with %d vertices\n", len(vertices))
    return true
}

UI_VERTEX_BINDING := vk.VertexInputBindingDescription{
    binding = 0,
    stride = size_of(TextVertex),
    inputRate = .VERTEX,
}

UI_VERTEX_ATTRIBUTES := [3]vk.VertexInputAttributeDescription{
    {
        binding = 0,
        location = 0,             
        format = .R32G32_SFLOAT,           
        offset = cast(u32)offset_of(TextVertex, pos),
    },
    {
        binding = 0,
        location = 1,
        format = .R32G32_SFLOAT,
        offset = cast(u32)offset_of(TextVertex, tex_coord),
    },
    {
        binding = 0,
        location = 2,
        format = .R32G32B32_SFLOAT,  
        offset = cast(u32)offset_of(TextVertex, color),
    },
}

}