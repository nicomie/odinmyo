package engine
import vk "vendor:vulkan"
import ttf "vendor:stb/truetype"
import "core:os"
import "core:fmt"
import "core:strings"
import "base:runtime"


Glyph :: struct {
    advance: f32,
    size: Vec2,
    bearing: Vec2,
    tex_coords: Vec4
}

FontMetrics :: struct {
    ascent, descent, line_gap, line_height: f32,
}

Font :: struct {
    data: []u8,
    info: ttf.fontinfo,
    scale: f32,
    metrics: FontMetrics,
    glyphs: [128]Glyph,
    texture: Texture,
    atlas_width, atlas_height: int
}

get_font_metrics :: proc(font_info: ^ttf.fontinfo, font_size: f32, scale: f32) -> FontMetrics {
    metrics: FontMetrics
    ascent_u, descent_u, line_gap_u: i32
    ttf.GetFontVMetrics(font_info, &ascent_u, &descent_u, &line_gap_u)
    
    metrics.ascent = f32(ascent_u) * scale
    metrics.descent = f32(descent_u) * scale
    metrics.line_gap = f32(line_gap_u) * scale
    metrics.line_height = metrics.ascent - metrics.descent + metrics.line_gap
    return metrics
}

TextVertex :: struct {
    pos: Vec2,
    tex_coord: Vec2,
    color: Vec3
}

TextUBO :: struct {
    projection: Mat4,
    view: Mat4
}


build_font_atlas :: proc(font: ^Font) -> []u8 {
    estimated_glyph_height := font.metrics.ascent - font.metrics.descent
    font.atlas_width, font.atlas_height = 512, 512  
    atlas_data := make([]u8, font.atlas_width * font.atlas_height)
    defer delete(atlas_data)

    x, y: i32
    max_row_height: i32

    for ch in 0..<128 {
        width, height, xoff, yoff: i32 
        advance, lsb: i32
        
        ttf.GetCodepointHMetrics(&font.info, rune(ch), &advance, &lsb)
        
        bitmap := ttf.GetCodepointBitmap(
            &font.info, 
            0, 
            font.scale, 
            rune(ch),
            &width, &height, &xoff, &yoff
        )
        
        if bitmap == nil {
            font.glyphs[ch] = Glyph{
                advance = f32(advance) * font.scale,
                size = {0, 0},
                bearing = {0, 0},
                tex_coords = {0, 0, 0, 0},
            }
            continue
        }
        
        if x + width >= i32(font.atlas_width) {
            x = 0
            y += max_row_height +1 
            max_row_height = 0
        }

        if height > max_row_height do max_row_height = height 

        for row in 0..<height {
            for col in 0..<width {
                if x + col < i32(font.atlas_width) && y + row < i32(font.atlas_height) {
                    idx := (y+row) * i32(font.atlas_width) + (x+col)
                    atlas_data[idx] = bitmap[row * width + col]
                }
            }
        }

        font.glyphs[ch] = Glyph{
            advance = f32(advance) * font.scale,
            size = {f32(width), f32(height)},
            bearing = {f32(xoff), f32(yoff)},
            tex_coords = {
                f32(x) / f32(font.atlas_width),
                f32(y) / f32(font.atlas_height),
                f32(x+width) / f32(font.atlas_width),
                f32(y+height) / f32(font.atlas_height)
            },
        }

        x += width + 1 
        ttf.FreeBitmap(bitmap, nil)
    
    }

    return atlas_data
}


createFontFromFile :: proc(
    ctx: ^Context,
    font_name: string,
    font_size: f32,
    name: string = "font",
) -> (font: Font, ok: bool) {
    
    font_path := strings.concatenate([]string{"engine/fonts/", font_name, ".ttf"})
    
    if !os.exists(font_path) {
        fmt.eprintf("Font file not found: %s\n", font_path)
        return font, false
    }
    
    fmt.printf("Found font: %s\n", font_path)
    
    font_data, success := os.read_entire_file_from_path(font_path, runtime.heap_allocator())
    if success != {} {
        fmt.eprintf("Failed to read font file: %s\n", font_path)
        return font, false
    }
    
    font.data = font_data

    if !ttf.InitFont(&font.info, raw_data(font.data), 0) {
        fmt.eprintln("stb_truetype failed to initialize font")
        return font, false
    }

    font.scale = ttf.ScaleForPixelHeight(&font.info, font_size)
    font.metrics = get_font_metrics(&font.info, font_size, font.scale)

    atlas_data := build_font_atlas(&font)

    createFontTextureImage(
        ctx, 
        &font.texture, 
        atlas_data,
        u32(font.atlas_width), 
        u32(font.atlas_height), 
        name,
    )

    fmt.printf("Loaded '%s' at size %.0f\n", font_name, font_size)
    return font, true
}

create_font_sampler :: proc(ctx: ^Context) -> vk.Sampler {
    
    sampler_info := vk.SamplerCreateInfo{
        sType = .SAMPLER_CREATE_INFO,
        magFilter = .LINEAR,
        minFilter = .LINEAR,
        mipmapMode = .LINEAR,         
        addressModeU = .CLAMP_TO_EDGE,
        addressModeV = .CLAMP_TO_EDGE,
        addressModeW = .CLAMP_TO_EDGE,
        mipLodBias = 0.0,
        anisotropyEnable = false,
        maxAnisotropy = 1.0,
        compareEnable = false,
        compareOp = .ALWAYS,
        minLod = 0.0,
        maxLod = 0.0,
        borderColor = .FLOAT_OPAQUE_BLACK,
        unnormalizedCoordinates = false,
    }

    sampler: vk.Sampler
    if vk.CreateSampler(ctx.vulkan.device, &sampler_info, nil, &sampler) != .SUCCESS {
        fmt.eprintln("ERROR: Failed to create font sampler")
        return 0
    }
    
    name_info := vk.DebugUtilsObjectNameInfoEXT{
        sType = .DEBUG_UTILS_OBJECT_NAME_INFO_EXT,
        objectType = .SAMPLER,
        objectHandle = cast(u64)sampler,
        pObjectName = "font_sampler",
    }
    vk.SetDebugUtilsObjectNameEXT(ctx.vulkan.device, &name_info)
    
    return sampler
}

free_font :: proc(ctx: ^Context, font: ^Font) {
    device := ctx.vulkan.device

    if font.texture.sampler != 0 {
        vk.DestroySampler(device, font.texture.sampler, nil)
    }
    
    if font.texture.view != 0 {
        vk.DestroyImageView(device, font.texture.view, nil)
    }
    
    if font.texture.handle.texture != 0 {
        vk.DestroyImage(device, font.texture.handle.texture, nil)
    }
    
    if font.texture.handle.memory != 0 {
        vk.FreeMemory(device, font.texture.handle.memory, nil)
    }
    
    if font.texture.uri != nil {
        delete(font.texture.uri)
    }
    
    if font.data != nil {
        delete(font.data)
    }
}

render_text :: proc(
    ctx: ^Context,
    font: ^Font,
    text: string,
    x, y: f32,
    color: Vec3,
) -> (vertices: [dynamic]TextVertex) {
    
    fmt.printf("Setting text color to: %.2f, %.2f, %.2f\n", color.x, color.y, color.z)
    cursor_x := x
    cursor_y := y + font.metrics.ascent

    for r in text {
        if r >= 128 do continue 
        
        glyph := &font.glyphs[r]
        
        if r == ' ' {
            cursor_x += glyph.advance
            continue
        }

        x_pos := cursor_x + glyph.bearing.x
        y_pos := cursor_y - (glyph.size.y + glyph.bearing.y)  // Position from bottom
        
        w := glyph.size.x
        h := glyph.size.y

        min_u := glyph.tex_coords.x
        min_v := glyph.tex_coords.y  
        max_u := glyph.tex_coords.z
        max_v := glyph.tex_coords.w
        
        // Top-left
        append(&vertices, TextVertex{{x_pos, y_pos}, {min_u, max_v}, color})
        // Bottom-left  
        append(&vertices, TextVertex{{x_pos, y_pos + h}, {min_u, min_v}, color})
        // Top-right
        append(&vertices, TextVertex{{x_pos + w, y_pos}, {max_u, max_v}, color})
        
        // Triangle 2
        // Bottom-left
        append(&vertices, TextVertex{{x_pos, y_pos + h}, {min_u, min_v}, color})
        // Top-right
        append(&vertices, TextVertex{{x_pos + w, y_pos}, {max_u, max_v}, color})
        // Bottom-right
        append(&vertices, TextVertex{{x_pos + w, y_pos + h}, {max_u, min_v}, color})
        
        cursor_x += glyph.advance
    }

    return vertices
}