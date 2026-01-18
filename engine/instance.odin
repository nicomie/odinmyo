package engine

import sdl "vendor:sdl2"
import vk "vendor:vulkan"
import "core:fmt"
import "core:os"


create_instance :: proc(using ctx: ^Context) {
    using ctx.platform
    using ctx.vulkan
    appInfo: vk.ApplicationInfo
    appInfo.sType = .APPLICATION_INFO
    appInfo.pApplicationName = "Hello triangle"
    appInfo.applicationVersion = vk.MAKE_VERSION(1, 0, 0)
    appInfo.pEngineName = "No Engine"
    appInfo.engineVersion = vk.MAKE_VERSION(1, 0, 0)
    appInfo.apiVersion = vk.API_VERSION_1_1

    createInfo: vk.InstanceCreateInfo
    createInfo.sType = .INSTANCE_CREATE_INFO
    createInfo.pApplicationInfo = &appInfo

    sdl2_extensions := get_sdlExtensions(window)
    allExtensions := make([dynamic]cstring)
    for el in sdl2_extensions {
        when ODIN_OS == .Darwin {
            if el != cstring("VK_KHR_display") {
                append_elem(&allExtensions, el)
            } 
        }
    }
    when ODIN_OS == .Darwin {
        append_elem(&allExtensions, cstring("VK_KHR_portability_enumeration"))
        append_elem(&allExtensions, cstring("VK_KHR_get_physical_device_properties2"))
    }

    createInfo.enabledExtensionCount = cast(u32)len(allExtensions)
    createInfo.ppEnabledExtensionNames = &allExtensions[0]
    createInfo.flags = {.ENUMERATE_PORTABILITY_KHR}

    debugCreateInfo: vk.DebugUtilsMessengerCreateInfoEXT
    when ODIN_DEBUG {
        layer_count: u32
        vk.EnumerateInstanceLayerProperties(&layer_count, nil) 
        layers := make([]vk.LayerProperties, layer_count)
        vk.EnumerateInstanceLayerProperties(&layer_count, raw_data(layers)) 

        outer: for name in VALIDATION_LAYERS {
            for &layer in layers {
                if name == cstring(&layer.layerName[0]) do continue outer;
            }
            fmt.eprintf("ERROR: validation layer %q not available\n", name);
			os.exit(1);
        }
        
		createInfo.enabledLayerCount = len(VALIDATION_LAYERS);
        createInfo.ppEnabledLayerNames = &VALIDATION_LAYERS[0];
		fmt.println("Validation Layers Loaded");

        populate_debug_messenger(&debugCreateInfo)
        createInfo.pNext = &debugCreateInfo
    } else {
		createInfo.enabledLayerCount = 0;
        createInfo.pNext = nil
    }
    if vk.CreateInstance(&createInfo, nil, &instance) != .SUCCESS {
        fmt.eprintln("failed to create instance: ", sdl.GetError())
        return 
    }
    fmt.println("Instances created");

}