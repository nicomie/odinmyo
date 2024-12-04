package main

import "core:fmt"
import "core:os"
import "base:runtime"
import sdl "vendor:sdl2"
import vk "vendor:vulkan"

USE_VALIDATION_LAYERS :: ODIN_DEBUG
WINDOW_WIDTH  :: 854
WINDOW_HEIGHT :: 480
VALIDATION_LAYERS := [?]cstring{"VK_LAYER_KHRONOS_validation"};
EXTENSIONS := [?]cstring{
    "VK_KHR_display", 
    "VK_EXT_debug_utils", 
}  
DEVICE_EXTENSIONS := [?]cstring{
    vk.KHR_SWAPCHAIN_EXTENSION_NAME
}


Context :: struct {
    window: ^sdl.Window,
    instance: vk.Instance,
    debugMessenger: vk.DebugUtilsMessengerEXT,
    physicalDevice: vk.PhysicalDevice,
    device: vk.Device,
    graphicsQueue: vk.Queue,
    surface: vk.SurfaceKHR,
    presentQueue: vk.Queue,
    swapchain: vk.SwapchainKHR,
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

populate_debug_messenger :: proc(info: ^vk.DebugUtilsMessengerCreateInfoEXT){
    info.sType = .DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT
    info.messageSeverity = {.VERBOSE, .WARNING, .ERROR}
    info.messageType = {.GENERAL, .VALIDATION, .PERFORMANCE}
    info.pfnUserCallback = debugCallback
}

setup_debug_messenger :: proc(using ctx: ^Context) {
    when ODIN_DEBUG {
        createInfo: vk.DebugUtilsMessengerCreateInfoEXT
        populate_debug_messenger(&createInfo)

        if CreateDebugUtilsMessengerEXT(instance, &createInfo, nil, &debugMessenger) != .SUCCESS {
            fmt.println("Failed to create debug utils messenger")
            return
        }
    }

}

create_instance :: proc(using ctx: ^Context) {
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

    sdl2_extensions := get_sdlExtensions(window)
    createInfo.enabledExtensionCount = cast(u32)len(sdl2_extensions)
    createInfo.ppEnabledExtensionNames = raw_data(sdl2_extensions)

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

get_sdlExtensions :: proc(window: ^sdl.Window) -> []cstring {
   
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

get_extensions :: proc() -> []vk.ExtensionProperties {
    n_ext: u32;
	vk.EnumerateInstanceExtensionProperties(nil, &n_ext, nil);
	extensions := make([]vk.ExtensionProperties, n_ext);
	vk.EnumerateInstanceExtensionProperties(nil, &n_ext, raw_data(extensions));
	
	return extensions;
}

pickPhysicalDevice :: proc(using ctx: ^Context) {
    deviceCount: u32 = 0
    result := vk.EnumeratePhysicalDevices(instance, &deviceCount, nil);
    if result != .SUCCESS {
        panic("Failed to enumerate physical devices!");
    }

    devices := make([]vk.PhysicalDevice, deviceCount) 
    vk.EnumeratePhysicalDevices(instance, &deviceCount, raw_data(devices))
    result = vk.EnumeratePhysicalDevices(instance, &deviceCount, nil);
    if result != .SUCCESS {
        panic("Failed to enumerate physical devices!");
    }
    for device in devices {
        if isDeviceSuitable(device, ctx) {
            physicalDevice = device
            break
        }
    }

    if physicalDevice == nil {
        fmt.println("failed to find a suitable GPU!");
        return
    }

}

createLogicalDevice :: proc(using ctx: ^Context) {
    indices := findQueueFamilies(physicalDevice, ctx)

    infos: [dynamic]vk.DeviceQueueCreateInfo
    uniqueQueueFamilies :[]u32 ={indices.graphicsFamily.?, indices.presentFamily.?}

    priority :f32 = 1
    for family in uniqueQueueFamilies {
        queueCreateInfo: vk.DeviceQueueCreateInfo
        queueCreateInfo.sType = .DEVICE_QUEUE_CREATE_INFO
        queueCreateInfo.queueFamilyIndex = family
        queueCreateInfo.queueCount = 1
        queueCreateInfo.pQueuePriorities = &priority
        append(&infos, queueCreateInfo)

    }

    deviceFeatures: vk.PhysicalDeviceFeatures

    createInfo: vk.DeviceCreateInfo
    createInfo.sType = .DEVICE_CREATE_INFO
    createInfo.queueCreateInfoCount = cast(u32)len(infos) 
    createInfo.pQueueCreateInfos = raw_data(infos)
    createInfo.pEnabledFeatures = &deviceFeatures 
    createInfo.enabledExtensionCount = cast(u32)len(DEVICE_EXTENSIONS)
    createInfo.ppEnabledExtensionNames =  &DEVICE_EXTENSIONS[0]

    if ODIN_DEBUG {
        createInfo.enabledLayerCount = len(VALIDATION_LAYERS)
        createInfo.ppEnabledLayerNames = &VALIDATION_LAYERS[0]
    } else {
        createInfo.enabledLayerCount = 0
    }

    if vk.CreateDevice(physicalDevice, &createInfo, nil, &device) != .SUCCESS {
        fmt.println("failed to create logical device")
        return 
    }

    vk.GetDeviceQueue(device, indices.graphicsFamily.?, 0, &graphicsQueue);
    vk.GetDeviceQueue(device, indices.presentFamily.?, 0, &presentQueue);

}


isDeviceSuitable :: proc(targetDevice: vk.PhysicalDevice, using ctx: ^Context) -> bool {
    indices := findQueueFamilies(targetDevice, ctx)

    extensionsSupported := checkDeviceExtensionSupport(targetDevice)

    ready := false
    if (extensionsSupported) {
        swapChainSupport := querySwapChainSupport(targetDevice, ctx)
        ready = len(swapChainSupport.formats) > 0 && len(swapChainSupport.presentModes) > 0
    }

    return ready && queueFamilyIndicesIsOk(indices)
}

checkDeviceExtensionSupport :: proc (device: vk.PhysicalDevice) -> bool {
    count: u32
    vk.EnumerateDeviceExtensionProperties(device, nil, &count, nil)

    availableExtensions := make([]vk.ExtensionProperties, count)
    vk.EnumerateDeviceExtensionProperties(device, nil, &count, raw_data(availableExtensions))

    requiredExtensions := map[string]bool{} 

    for ext in DEVICE_EXTENSIONS do requiredExtensions[string(ext)] = false


    for &available in availableExtensions {
        requiredExtensions[string(cstring(&available.extensionName[0]))] = true
    }

    allFound := true
    for value in requiredExtensions {
        if requiredExtensions[value] == false do allFound = false 
    }

    return allFound

}

QueueFamilyIndices :: struct {
    graphicsFamily: Maybe(u32),
    presentFamily: Maybe(u32),
}

queueFamilyIndicesIsOk :: proc(indices: QueueFamilyIndices) -> bool {
    if indices.graphicsFamily != nil && indices.presentFamily != nil {
        return true;
    } else {
        return false;
    }
}

findQueueFamilies :: proc(target: vk.PhysicalDevice, using ctx: ^Context) -> QueueFamilyIndices {
    indices: QueueFamilyIndices;
    count: u32;
    vk.GetPhysicalDeviceQueueFamilyProperties(target, &count, nil)

    families:= make([]vk.QueueFamilyProperties, count);
    vk.GetPhysicalDeviceQueueFamilyProperties(target, &count, raw_data(families))

    i:u32 = 0;
    for family in families {
        if .GRAPHICS in family.queueFlags{
            indices.graphicsFamily = i;
        }
        presentSupport : b32= false
        vk.GetPhysicalDeviceSurfaceSupportKHR(target, i, surface, &presentSupport)
        if presentSupport do indices.presentFamily = i

        if queueFamilyIndicesIsOk(indices) do break
        i+=1;
    }
  
    return indices;
}

createSurface :: proc(using ctx: ^Context) {
    if sdl.Vulkan_CreateSurface(window, instance, &surface) != true {
        fmt.println("failed to create window surface")
        return 
    }
}

SwapChainSupportDetails :: struct {
    capabilities: vk.SurfaceCapabilitiesKHR,
    formats: []vk.SurfaceFormatKHR,
    presentModes: []vk.PresentModeKHR,
}

querySwapChainSupport :: proc(target: vk.PhysicalDevice, using ctx: ^Context) -> SwapChainSupportDetails{
    details: SwapChainSupportDetails
    
    vk.GetPhysicalDeviceSurfaceCapabilitiesKHR(target, surface, &details.capabilities)

    formatCount: u32 
    vk.GetPhysicalDeviceSurfaceFormatsKHR(target, surface, &formatCount, nil)

    details.formats  = make([]vk.SurfaceFormatKHR, formatCount)
    if formatCount > 0  {
        vk.GetPhysicalDeviceSurfaceFormatsKHR(target, surface, &formatCount, raw_data(details.formats))
    }

    presentModeCount: u32 
    vk.GetPhysicalDeviceSurfacePresentModesKHR(target, surface, &presentModeCount, nil)

	details.presentModes = make([]vk.PresentModeKHR, presentModeCount);
    if presentModeCount != 0  {
        vk.GetPhysicalDeviceSurfacePresentModesKHR(target, surface, &presentModeCount, raw_data(details.presentModes))
    }

    return details
}

chooseSwapSurfaceFormat :: proc(availableFormats: ^[]vk.SurfaceFormatKHR) -> vk.SurfaceFormatKHR {
    for format in availableFormats {
        if format.format == .B8G8R8A8_SRGB && format.colorSpace == .SRGB_NONLINEAR {
            return format
        } 
    }
    
    return availableFormats[0]
}

chooseSwapPresentMode :: proc(modes: ^[]vk.PresentModeKHR) -> vk.PresentModeKHR {
    for mode in modes {
        if mode == .MAILBOX do return mode
    }
    return .FIFO
}

chooseSwapExtent :: proc(using ctx: ^Context, capabilities: ^vk.SurfaceCapabilitiesKHR) -> vk.Extent2D {
   if capabilities.currentExtent.width != max(u32) {
        return capabilities.currentExtent
   } else {
    w,h : i32
    sdl.GL_GetDrawableSize(window, &w, &h)
    extent := vk.Extent2D {
        width = cast(u32) w,
        height = cast(u32) h,
    }
    extent.width = clamp(extent.width, capabilities.minImageExtent.width, capabilities.maxImageExtent.width)
    extent.height = clamp(extent.height, capabilities.minImageExtent.height, capabilities.maxImageExtent.height)

    return extent

   } 
}


clamp :: proc(value, min, max: u32) -> u32  {
    if value < min {
        return min;
    }
    if value > max {
        return max;
    }
    return value;
}  

createSwapChain :: proc(using ctx: ^Context) {
    swapChainSupport := querySwapChainSupport(physicalDevice, ctx)

    surfaceFormat := chooseSwapSurfaceFormat(&swapChainSupport.formats)
    presentMode := chooseSwapPresentMode(&swapChainSupport.presentModes)
    extent := chooseSwapExtent(ctx, &swapChainSupport.capabilities)

    imageCount := swapChainSupport.capabilities.minImageCount + 1
    if swapChainSupport.capabilities.maxImageCount > 0 && 
    imageCount > swapChainSupport.capabilities.maxImageCount {
        imageCount = swapChainSupport.capabilities.maxImageCount
    }

    createInfo: vk.SwapchainCreateInfoKHR
    createInfo.sType = .SWAPCHAIN_CREATE_INFO_KHR
    createInfo.surface = surface
    createInfo.minImageCount = imageCount;
    createInfo.imageFormat = surfaceFormat.format;
    createInfo.imageColorSpace = surfaceFormat.colorSpace;
    createInfo.imageExtent = extent;
    createInfo.imageArrayLayers = 1;
    createInfo.imageUsage = {.COLOR_ATTACHMENT};

    indices := findQueueFamilies(physicalDevice, ctx)
    queueFamilyIndices := []u32{indices.graphicsFamily.?, indices.presentFamily.?}

    if indices.graphicsFamily != indices.presentFamily {
        createInfo.imageSharingMode = .CONCURRENT
        createInfo.queueFamilyIndexCount = 2
        createInfo.pQueueFamilyIndices = &queueFamilyIndices[0]
    } else {
        createInfo.imageSharingMode = .EXCLUSIVE
        createInfo.queueFamilyIndexCount = 0
        createInfo.pQueueFamilyIndices = nil
    }

    createInfo.preTransform = swapChainSupport.capabilities.currentTransform
    createInfo.compositeAlpha = {.OPAQUE}
    createInfo.presentMode = presentMode
    createInfo.clipped = true
    createInfo.oldSwapchain = vk.SwapchainKHR{};

    if vk.CreateSwapchainKHR(device, &createInfo, nil, &swapchain) != .SUCCESS {
        fmt.eprintln("failed to create swapchain")
        return
    }

}

initVulkan :: proc(using ctx: ^Context) {

    getInstanceProcAddr := sdl.Vulkan_GetVkGetInstanceProcAddr()
    assert(getInstanceProcAddr != nil)
    vk.load_proc_addresses(getInstanceProcAddr)
    create_instance(ctx)

    vk.load_proc_addresses(instance)
    setup_debug_messenger(ctx)
        
    fmt.println("Available extensions")
    extensions := get_extensions();
    for _, i in extensions do fmt.println(cstring(&extensions[i].extensionName[0]))

    createSurface(ctx)
    pickPhysicalDevice(ctx)
    createLogicalDevice(ctx)
    createSwapChain(ctx)

}

debugCallback :: proc "cdecl" (
    messageSeverity: vk.DebugUtilsMessageSeverityFlagsEXT,
    messageTypes: vk.DebugUtilsMessageTypeFlagsEXT,
    pCallbackData: ^vk.DebugUtilsMessengerCallbackDataEXT,
    pUserData: rawptr
) -> b32 {
    context = runtime.default_context()
    fmt.printf("Vulkan Validation Layer Message: %s\n", string(pCallbackData.pMessage))
    return false 
}

CreateDebugUtilsMessengerEXT :: proc(
    instance: vk.Instance,
    pCreateInfo: ^vk.DebugUtilsMessengerCreateInfoEXT,
    pAllocator: ^vk.AllocationCallbacks,
    pDebugMessenger: ^vk.DebugUtilsMessengerEXT
) -> vk.Result {
    // Retrieve the function pointer for vkCreateDebugUtilsMessengerEXT
    func := cast(vk.ProcCreateDebugUtilsMessengerEXT)(vk.GetInstanceProcAddr(instance, "vkCreateDebugUtilsMessengerEXT"))
    
    if func != nil {
        return func(instance, pCreateInfo, pAllocator, pDebugMessenger)
    } else {
        return .ERROR_EXTENSION_NOT_PRESENT
    }
}

DestroyDebugUtilsMessengerEXT :: proc(
    instance: vk.Instance,
    debugMessenger: vk.DebugUtilsMessengerEXT,
    pAllocator: ^vk.AllocationCallbacks
){
    func := cast(vk.ProcDestroyDebugUtilsMessengerEXT)(vk.GetInstanceProcAddr(instance, "vkDestroyDebugUtilsMessengerEXT"))
    
    if func != nil {
        func(instance, debugMessenger, pAllocator)
    } else {
            fmt.println("destroy not found?")

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
    vk.DestroySwapchainKHR(device, swapchain, nil)
    vk.DestroyDevice(device, nil)
    when ODIN_DEBUG {
       DestroyDebugUtilsMessengerEXT(instance, debugMessenger, nil)
    }
    vk.DestroySurfaceKHR(instance, surface, nil)
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