package app

import vk "vendor:vulkan"
import sdl "vendor:sdl2"
import "core:fmt"
import "core:os"


WINDOW_WIDTH  :: 854
WINDOW_HEIGHT :: 480
MAX_FRAMES_IN_FLIGHT :: 2
VALIDATION_LAYERS := [?]cstring{"VK_LAYER_KHRONOS_validation"};
EXTENSIONS := [?]cstring{
    "VK_KHR_display", 
    "VK_KHR_surface", 
    "VK_KHR_xcb_surface", 
    "VK_EXT_debug_utils", 
}  
DEVICE_EXTENSIONS := [?]cstring{
    vk.KHR_SWAPCHAIN_EXTENSION_NAME
}

check_vk :: proc(result: vk.Result, location := #caller_location) {
    if result != .SUCCESS {
        fmt.eprintf("Vulkan error at %s: %v\n", location, result)
        os.exit(1)
    }
}

Status :: enum {
    BEGIN,
    END
}

t :: proc(status: Status, method: string) {
   if status == .BEGIN {
    fmt.printf("starting %v \n", method)
   } else {
    fmt.printf("completed %v \n", method)
   }
}

get_sdl_extensions :: proc(window: ^sdl.Window) -> []cstring {
   
    extension_count: u32
    if sdl.Vulkan_GetInstanceExtensions(window, &extension_count, nil) == false {
        fmt.eprintln("SDL_Vulkan_GetInstanceExtensions failed: ", sdl.GetError())
    } 
    additionalCount : u32 = 0
    if ODIN_DEBUG {
        additionalCount = len(EXTENSIONS)
    }
    totalCount := extension_count+additionalCount
    extensions := make([]cstring, totalCount)
    if sdl.Vulkan_GetInstanceExtensions(window, &extension_count, raw_data(extensions)) == false {
        fmt.eprintln("SDL_Vulkan_GetInstanceExtensions failed: ", sdl.GetError())
    }       
        
    if ODIN_DEBUG {
        for i in 0..<additionalCount{
            extensions[totalCount-i-1] = EXTENSIONS[i]
        } 
    } 

    for &ex in extensions do fmt.println(string(ex))

    return extensions
}