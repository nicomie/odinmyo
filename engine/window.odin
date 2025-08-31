package engine

import sdl "vendor:sdl2"
import vk "vendor:vulkan"
import "core:fmt"
import "core:os"

WINDOW_WIDTH  :: 1280
WINDOW_HEIGHT :: 720

initWindow :: proc (ctx: ^Context) {
    using ctx.platform
    if sdl.Init(sdl.INIT_VIDEO) != 0 {
        fmt.eprintln("sdl_Init failed: ", sdl.GetError())
        return
    }

    // Create window
    sdlWindow := sdl.CreateWindow("Odin Vulkan Engine", sdl.WINDOWPOS_UNDEFINED, 
    sdl.WINDOWPOS_UNDEFINED, WINDOW_WIDTH, WINDOW_HEIGHT, {.VULKAN, .RESIZABLE})

    fmt.println(window)
    if sdlWindow == nil {
        fmt.eprintln("Failed to create window: ", sdl.GetError())
        return
    }

    window = sdlWindow
}