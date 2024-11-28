package main

import "core:fmt"
import "core:os"
import sdl "vendor:sdl2"
import vk "vendor:vulkan"

USE_VALIDATION_LAYERS :: ODIN_DEBUG
WINDOW_WIDTH  :: 854
WINDOW_HEIGHT :: 480

Context :: struct {
    window: ^sdl.Window,
    instance: vk.Instance,
    debugMessenger: vk.DebugUtilsMessengerEXT,
}

initWindow :: proc (ctx: ^Context) {
    if sdl.Init(sdl.INIT_VIDEO) != 0 {
        fmt.eprintln("sdl_Init failed: ", sdl.GetError())
        return
    }

    // Create window
    window := sdl.CreateWindow("Odin sdl2 Wayland Demo", sdl.
    WINDOWPOS_UNDEFINED, sdl.WINDOWPOS_UNDEFINED, WINDOW_WIDTH, WINDOW_HEIGHT, sdl.WINDOW_VULKAN)

    fmt.println(window)
    if window == nil {
        fmt.eprintln("Failed to create window: ", sdl.GetError())
        return
    }

    ctx.window = window
}

initVulkan :: proc(using ctx: ^Context) {

    { // create instance
        getInstanceProcAddr := sdl.Vulkan_GetVkGetInstanceProcAddr()
        assert(getInstanceProcAddr != nil)

        vk.load_proc_addresses(getInstanceProcAddr)
        assert(vk.CreateInstance != nil)

        vkInstance: vk.Instance
        appInfo: vk.ApplicationInfo
        appInfo.sType = .APPLICATION_INFO
        appInfo.pApplicationName = "Hello triangle"
        appInfo.applicationVersion = vk.MAKE_VERSION(1, 0, 0)
        appInfo.pEngineName = "No Engine"
        appInfo.engineVersion = vk.MAKE_VERSION(1, 0, 0)
        appInfo.apiVersion = vk.API_VERSION_1_0

        createInfo: vk.InstanceCreateInfo
        createInfo.sType = .INSTANCE_CREATE_INFO
        createInfo.pApplicationInfo = &appInfo

        extension_count: u32
        if sdl.Vulkan_GetInstanceExtensions(window, &extension_count, nil) == false {
            fmt.eprintln("SDL_Vulkan_GetInstanceExtensions failed: ", sdl.GetError())
            return 
        } 

        additionalCount : u32 = 0
        if ODIN_DEBUG {
            additionalCount = 1
        }
        totalCount := extension_count+additionalCount
        extensions := make([]cstring, totalCount)
        if sdl.Vulkan_GetInstanceExtensions(window, &extension_count, raw_data(extensions)) == false {
            fmt.eprintln("SDL_Vulkan_GetInstanceExtensions failed: ", sdl.GetError())
            return
        }       
        
        if ODIN_DEBUG {
            extensions[totalCount-1] = vk.EXT_DEBUG_UTILS_EXTENSION_NAME
        } 
          
        fmt.println("Available extensions")
        for e in extensions {
                fmt.println(e, "\n")
        }

        fmt.println(len(extensions))
        createInfo.enabledExtensionCount = cast(u32)len(extensions)
        createInfo.ppEnabledExtensionNames = raw_data(extensions)

        extension_count2: u32
        vk.EnumerateInstanceExtensionProperties(nil, &extension_count2, nil)
        fmt.printf("count %d", extension_count2)
        extensions2 := make([]vk.ExtensionProperties, extension_count2)
        vk.EnumerateInstanceExtensionProperties(nil, &extension_count2, raw_data(extensions2))

        fmt.println("Available extensions\n")
        for _, i in extensions2{
            cstr := cstring(&extensions2[i].extensionName[0])
            fmt.print(string(cstr), "\n");
        } 

        layer_count: u32
        vk.EnumerateInstanceLayerProperties(&layer_count, nil) 

        layers := make([]vk.LayerProperties, layer_count)
        vk.EnumerateInstanceLayerProperties(&layer_count, raw_data(layers)) 
        
        found := false
        for _, i in &layers {
            if "VK_LAYER_KHRONOS_validation" == string(cstring(&layers[i].layerName[0])) {
                found = true
            }
        }

        if (ODIN_DEBUG && !found) {
             fmt.println("Validation layers requested but not available")
             return 
        }

        debugCreateInfo: vk.DebugUtilsMessengerCreateInfoEXT
        if ODIN_DEBUG {
            createInfo.enabledLayerCount = layer_count
            convertedString: cstring = "VK_LAYER_KHRONOS_validation"
            createInfo.ppEnabledLayerNames = &convertedString

            debugCreateInfo.sType = .DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT
            debugCreateInfo.messageSeverity = {.VERBOSE, .WARNING, .ERROR}
            debugCreateInfo.messageType = {.GENERAL, .VALIDATION, .PERFORMANCE}
            debugCreateInfo.pfnUserCallback = debugCallback;
            createInfo.pNext = &debugCreateInfo 
        } else {
            createInfo.enabledLayerCount = 0
            createInfo.pNext = nil
        }

        if vk.CreateInstance(&createInfo, nil, &vkInstance) != .SUCCESS {
            fmt.eprintln("failed to create instance: ", sdl.GetError())
            return 
        }

        { // setup debug messenger
                messengerDebugInfo: vk.DebugUtilsMessengerCreateInfoEXT
            if ODIN_DEBUG {
                messengerDebugInfo: vk.DebugUtilsMessengerCreateInfoEXT
                messengerDebugInfo.sType = .DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT
                messengerDebugInfo.messageSeverity = {.VERBOSE, .WARNING, .ERROR}
                messengerDebugInfo.messageType = {.GENERAL, .VALIDATION, .PERFORMANCE}
                messengerDebugInfo.pfnUserCallback = debugCallback;

                if CreateDebugUtilsMessengerEXT(instance, &messengerDebugInfo, nil, &debugMessenger) != .SUCCESS {
                    fmt.println("Validation layers requested but not available")
                    return 
                }


            }
        }
    }  

}

debugCallback :: proc "cdecl" (
    messageSeverity: vk.DebugUtilsMessageSeverityFlagsEXT,
    messageTypes: vk.DebugUtilsMessageTypeFlagsEXT,
    pCallbackData: ^vk.DebugUtilsMessengerCallbackDataEXT,
    pUserData: rawptr
) -> b32 {
    return false // or true if you want to prevent Vulkan from handling further
}

CreateDebugUtilsMessengerEXT :: proc(
    instance: vk.Instance,
    pCreateInfo: ^vk.DebugUtilsMessengerCreateInfoEXT,
    pAllocator: ^vk.AllocationCallbacks,
    pDebugMessenger: ^vk.DebugUtilsMessengerEXT
) -> vk.Result {
    // Retrieve the function pointer for vkCreateDebugUtilsMessengerEXT
    func := cast(vk.ProcCreateDebugUtilsMessengerEXT)(
        vk.GetInstanceProcAddr(instance, "vkCreateDebugUtilsMessengerEXT")
    )
    
    // Check if the function pointer is valid
    if func != nil {
        // Call the function
        return func(instance, pCreateInfo, pAllocator, pDebugMessenger)
    } else {
        // Return error if the extension is not present
        return .ERROR_EXTENSION_NOT_PRESENT
    }
}

DestroyDebugUtilsMessengerEXT :: proc(
    instance: vk.Instance,
    debugMessenger: vk.DebugUtilsMessengerEXT,
    pAllocator: ^vk.AllocationCallbacks
) {
    // Retrieve the function pointer for vkDestroyDebugUtilsMessengerEXT
    func := cast(vk.ProcDestroyDebugUtilsMessengerEXT)(
        vk.GetInstanceProcAddr(instance, "vkDestroyDebugUtilsMessengerEXT")
    )
    
    // Check if the function pointer is valid
    if func != nil {
        // Call the function
        func(instance, debugMessenger, pAllocator)
    }
}

run :: proc(using ctx: ^Context) {
    loop: for {
         event: sdl.Event
         for sdl.PollEvent(&event) {
            #partial switch event.type {
                case .KEYDOWN:
                    #partial switch event.key.keysym.sym {
                        case .ESCAPE:
                            break loop
                    }
                case .QUIT:
                    break loop
            }            
         }
    }
}

exit :: proc(using ctx: ^Context) {
    if ODIN_DEBUG {
        DestroyDebugUtilsMessengerEXT(instance, debugMessenger, nil)
    }
    vk.DestroyInstance(instance, nil)
    sdl.DestroyWindow(window)
    sdl.Quit()
}

main :: proc() {
    ctx: Context = Context {}
    initWindow(&ctx)
    initVulkan(&ctx)
    defer exit(&ctx);

    run(&ctx);
   
}