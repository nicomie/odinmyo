#+feature dynamic-literals
package app

import "core:fmt"
import "core:c"
import "core:os"
import "core:time"
import "base:runtime"
import "core:strings"

import sdl "vendor:sdl2"
import vk "vendor:vulkan"

QueueFamily :: enum {
    Graphics,
    Present,
}

Renderer :: struct {
    start: time.Time,
    window: ^sdl.Window,
    
    instance: vk.Instance,
    physicalDevice: vk.PhysicalDevice,
    device: vk.Device,
    surface: vk.SurfaceKHR,
    
    graphics_queue: vk.Queue,
    present_queue: vk.Queue,
    queueIndices: [QueueFamily]int,
    
    imageAvailableSemaphores: [MAX_FRAMES_IN_FLIGHT]vk.Semaphore,
    renderFinishedSemaphores: [MAX_FRAMES_IN_FLIGHT]vk.Semaphore,
    inFlightFences: [MAX_FRAMES_IN_FLIGHT]vk.Fence,
    commandBuffers: [MAX_FRAMES_IN_FLIGHT]vk.CommandBuffer,
    currentFrame: u32,
    framebufferResized: bool,

    swapchain: Swapchain,
    camera: Camera,
    texture: Texture,

    commandPool: vk.CommandPool,
    descriptor_pool: DescriptorPool,
    descriptor_set_layouts: map[PipelineType]vk.DescriptorSetLayout,
    descriptor_sets: [MAX_FRAMES_IN_FLIGHT]vk.DescriptorSet,

    render_pass: Pass,
    meshes: [dynamic]MeshObject,

    depthImage: DepthImage,
    colorImage: DepthImage,

    debugMessenger: vk.DebugUtilsMessengerEXT,

}

add_descriptor_set_layout :: proc(r: ^Renderer, type: PipelineType, set: vk.DescriptorSetLayout) {
    r.descriptor_set_layouts[type] = set
}

set_command_pool :: proc(r: ^Renderer, pool: vk.CommandPool) {
    r.commandPool = pool
}

init_renderer :: proc(r: ^Renderer, title: string, width, height: i32, start_time: time.Time) -> bool {
    if sdl.Init(sdl.INIT_VIDEO) != 0 {
        fmt.eprintln("SDL_Init failed:", sdl.GetError())
        return false
    }
    fmt.println("sdl initated")

    r.start = start_time
    
    r.window = sdl.CreateWindow(strings.clone_to_cstring(title), sdl.WINDOWPOS_UNDEFINED, sdl.WINDOWPOS_UNDEFINED, 
                               width, height, {.VULKAN, .RESIZABLE})
    if r.window == nil {
        fmt.eprintln("Failed to create window:", sdl.GetError())
        return false
    }
    fmt.println("window initated")

    
    if !init_vulkan(r) {
        return false
    }
    fmt.println("vk initated")
    
    return true
}

init_descriptors :: proc(r: ^Renderer) -> bool {
    pool_sizes := DescriptorPoolSizes{
        .UniformBuffer        = 100, 
        .CombinedImageSampler = 50,  
        .StorageBuffer       = 20,   
    }

    pool, err := create_pool(r, pool_sizes, max_sets=200)
    if err != .SUCCESS do return false
    r.descriptor_pool = pool

    r.descriptor_set_layouts[PipelineType.Main] = create_main_descriptor_layout(r)

    for i in 0..<MAX_FRAMES_IN_FLIGHT {
        r.descriptor_sets = allocate_descriptor_sets(r, PipelineType.Main, MAX_FRAMES_IN_FLIGHT)
    }
    return true
}

create_instance :: proc(using r: ^Renderer) {
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

    sdl2_extensions := get_sdl_extensions(window)
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

init_vulkan :: proc(r: ^Renderer) -> bool {

    getInstanceProcAddr := sdl.Vulkan_GetVkGetInstanceProcAddr()
    assert(getInstanceProcAddr != nil)
    vk.load_proc_addresses(getInstanceProcAddr)
    create_instance(r)
    vk.load_proc_addresses(r.instance)

    when ODIN_DEBUG {
        setup_debug_messenger(r)
    }

    create_surface(r)
    pick_physical_device(r)
    fmt.println("physical device initated")

    create_logical_device(r)
    fmt.println("logical device initated")

    r.commandPool = create_command_pool(r)
    fmt.println("command pool initated")

    create_sync_objects(r)
    fmt.println("sync initated")

   
    return true
}

populate_debug_messenger :: proc(info: ^vk.DebugUtilsMessengerCreateInfoEXT){
    info.sType = .DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT
    info.messageSeverity = {.VERBOSE, .WARNING, .ERROR}
    info.messageType = {.GENERAL, .VALIDATION, .PERFORMANCE}
    info.pfnUserCallback = debug_callback
}

debug_callback :: proc "cdecl" (
    messageSeverity: vk.DebugUtilsMessageSeverityFlagsEXT,
    messageTypes: vk.DebugUtilsMessageTypeFlagsEXT,
    pCallbackData: ^vk.DebugUtilsMessengerCallbackDataEXT,
    pUserData: rawptr
) -> b32 {
    context = runtime.default_context()
    fmt.printf("Vulkan Validation Layer Message: %s\n", string(pCallbackData.pMessage))
    return false 
}

setup_debug_messenger :: proc(r: ^Renderer) {
    createInfo: vk.DebugUtilsMessengerCreateInfoEXT
    populate_debug_messenger(&createInfo)

    if create_debug_utils_messenger_EXT(r.instance, &createInfo, nil, &r.debugMessenger) != .SUCCESS {
        fmt.println("Failed to create debug utils messenger")
        return
    }
}

create_debug_utils_messenger_EXT :: proc(
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

create_surface :: proc(r: ^Renderer) {
    if sdl.Vulkan_CreateSurface(r.window, r.instance, &r.surface) != true {
        fmt.println("failed to create window surface")
        return 
    }
    fmt.println("surface initated")

}

check_device_extension_support :: proc (device: vk.PhysicalDevice) -> bool {
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

pick_physical_device :: proc(r: ^Renderer) {
    deviceCount: u32 = 0
    result := vk.EnumeratePhysicalDevices(r.instance, &deviceCount, nil);
    if result != .SUCCESS {
        panic("Failed to enumerate physical devices!");
    }

    devices := make([]vk.PhysicalDevice, deviceCount) 
    vk.EnumeratePhysicalDevices(r.instance, &deviceCount, raw_data(devices))
    result = vk.EnumeratePhysicalDevices(r.instance, &deviceCount, nil);
    if result != .SUCCESS {
        panic("Failed to enumerate physical devices!");
    }
 
    suitability :: proc(using r: ^Renderer, dev: vk.PhysicalDevice) -> int {
        props: vk.PhysicalDeviceProperties  
        features: vk.PhysicalDeviceFeatures
        vk.GetPhysicalDeviceProperties(dev, &props)
        vk.GetPhysicalDeviceFeatures(dev, &features)

        score := 0
        if props.deviceType == .DISCRETE_GPU do score += 1000
        score += cast(int)props.limits.maxImageDimension2D

        if !features.fillModeNonSolid do return 0
        if !features.geometryShader do return 0
		if !check_device_extension_support(dev) do return 0
        if !features.samplerAnisotropy do return 0

        details := query_swapchain_support(dev, r)
        if len(details.formats) == 0 || len(details.presentModes) == 0 do return 0

        return score

    }

    hiscore := 0
    for dev in devices {
        score := suitability(r, dev)
        if score > hiscore {
            r.physicalDevice = dev
            msaa := get_usable_sample_count(dev)
            hiscore = score
        }
    }

    if hiscore == 0 {
        fmt.println("failed to find a suitable GPU!");
        os.exit(1)

    }
}

get_usable_sample_count :: proc(physicalDevice: vk.PhysicalDevice) -> vk.SampleCountFlags {
    props : vk.PhysicalDeviceProperties 
    vk.GetPhysicalDeviceProperties(physicalDevice, &props) 

    counts := props.limits.framebufferColorSampleCounts & props.limits.framebufferDepthSampleCounts

    if (counts & vk.SampleCountFlags{vk.SampleCountFlag._64} != vk.SampleCountFlags{}) do return {._64}
    if (counts & vk.SampleCountFlags{vk.SampleCountFlag._32} != vk.SampleCountFlags{}) do return {._32}    
    if (counts & vk.SampleCountFlags{vk.SampleCountFlag._16} != vk.SampleCountFlags{}) do return {._16}
    if (counts & vk.SampleCountFlags{vk.SampleCountFlag._8} != vk.SampleCountFlags{}) do return {._8}
    if (counts & vk.SampleCountFlags{vk.SampleCountFlag._4} != vk.SampleCountFlags{}) do return {._4}
    if (counts & vk.SampleCountFlags{vk.SampleCountFlag._2} != vk.SampleCountFlags{}) do return {._2}

    return {._1}
}

find_queue_families :: proc(r: ^Renderer) {
    count: u32;
    vk.GetPhysicalDeviceQueueFamilyProperties(r.physicalDevice, &count, nil)

    families:= make([]vk.QueueFamilyProperties, count);
    vk.GetPhysicalDeviceQueueFamilyProperties(r.physicalDevice, &count, raw_data(families))
 
    for family, i in families {
        if .GRAPHICS in family.queueFlags && r.queueIndices[.Graphics] == -1 do r.queueIndices[.Graphics] = i

        presentSupport : b32 = false
        vk.GetPhysicalDeviceSurfaceSupportKHR(r.physicalDevice, u32(i), r.surface, &presentSupport)
        if presentSupport && r.queueIndices[.Present] == -1 do r.queueIndices[.Present] = i

        for q in r.queueIndices do if q == -1 do continue
    }
       


}

create_logical_device :: proc(using r: ^Renderer) {
    find_queue_families(r)
    fmt.println("queue families initated")

    infos: [dynamic]vk.DeviceQueueCreateInfo
    uniqueQueueFamilies := map[int]bool{}
    for i in queueIndices do uniqueQueueFamilies[i] = true

    priority :f32 = 1
    for family, _ in uniqueQueueFamilies {
        queueCreateInfo: vk.DeviceQueueCreateInfo
        queueCreateInfo.sType = .DEVICE_QUEUE_CREATE_INFO
        queueCreateInfo.queueFamilyIndex = u32(family)
        queueCreateInfo.queueCount = 1
        queueCreateInfo.pQueuePriorities = &priority
        append(&infos, queueCreateInfo)

    }

    deviceFeatures: vk.PhysicalDeviceFeatures
    deviceFeatures.samplerAnisotropy = true
    deviceFeatures.sampleRateShading = true
    deviceFeatures.fillModeNonSolid = true
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
    fmt.println("logical device initated inside")


    vk.GetDeviceQueue(device, u32(queueIndices[.Graphics]), 0, &graphics_queue);
    vk.GetDeviceQueue(device, u32(queueIndices[.Present]), 0, &present_queue);

}

create_sync_objects :: proc(r: ^Renderer) {
    semaphoreInfo: vk.SemaphoreCreateInfo
    semaphoreInfo.sType = .SEMAPHORE_CREATE_INFO

    fenceInfo: vk.FenceCreateInfo
    fenceInfo.sType = .FENCE_CREATE_INFO
    fenceInfo.flags = {.SIGNALED}

    for i in 0..<MAX_FRAMES_IN_FLIGHT {
        if vk.CreateSemaphore(r.device, &semaphoreInfo, nil, &r.imageAvailableSemaphores[i]) != .SUCCESS ||
        vk.CreateSemaphore(r.device, &semaphoreInfo, nil, &r.renderFinishedSemaphores[i]) != .SUCCESS ||
        vk.CreateFence(r.device, &fenceInfo, nil, &r.inFlightFences[i]) != .SUCCESS {
            fmt.eprintln("failed to create semaphores")
            os.exit(1)
        }
    }
}

destroy_renderer :: proc(r: ^Renderer) {
    vk.DeviceWaitIdle(r.device)
    
    // Cleanup Vulkan resources
    // Destroy SDL window
    sdl.DestroyWindow(r.window)
    sdl.Quit()
}

FrameData :: struct {
    image_available: [MAX_FRAMES_IN_FLIGHT]vk.Semaphore,
    render_finished: [MAX_FRAMES_IN_FLIGHT]vk.Semaphore,
    in_flight: [MAX_FRAMES_IN_FLIGHT]vk.Fence,
    command_buffer: [MAX_FRAMES_IN_FLIGHT]vk.CommandBuffer,
}

draw_frame :: proc(using r: ^Renderer) {
    imageIndex := begin_frame(r)
    if int(imageIndex) == -1 {
        fmt.println("OI")
        return
    }
    fmt.println("ABRA")
    update_camera(r, imageIndex)

    record_command_buffer(r, r.commandBuffers[currentFrame], imageIndex)
    end_frame(r, imageIndex)
}

begin_frame :: proc(using r: ^Renderer) -> u32 {
    vk.WaitForFences(r.device, 1, &r.inFlightFences[r.currentFrame], true, max(u64))
    vk.ResetFences(device, 1, &inFlightFences[currentFrame])

    image_index: u32
    res := vk.AcquireNextImageKHR(device, swapchain.handle, max(u64), imageAvailableSemaphores[currentFrame], {}, &image_index)
    if res == .ERROR_OUT_OF_DATE_KHR {
        recreate_swapchain(r)
        return image_index
    } else if res != .SUCCESS && res != .SUBOPTIMAL_KHR {
        fmt.eprintln("failed to acquire swapchain image")
        os.exit(1)
    }

    vk.ResetCommandBuffer(commandBuffers[currentFrame], {})

    return image_index
}

end_frame :: proc(using r: ^Renderer, idx: u32) {
    idx_ref := idx
    waitSemaphores := [?]vk.Semaphore{imageAvailableSemaphores[currentFrame]}
    waitStages := [?]vk.PipelineStageFlags{{.COLOR_ATTACHMENT_OUTPUT}}

    submitInfo : vk.SubmitInfo 
    submitInfo.sType = .SUBMIT_INFO
    submitInfo.waitSemaphoreCount = 1
    submitInfo.pWaitSemaphores= &waitSemaphores[0] 
    submitInfo.pWaitDstStageMask = &waitStages[0]
    submitInfo.commandBufferCount = 1
    submitInfo.pCommandBuffers = &commandBuffers[currentFrame]

    signalSemaphores := [?]vk.Semaphore{renderFinishedSemaphores[currentFrame]}
    submitInfo.signalSemaphoreCount = 1
    submitInfo.pSignalSemaphores = &signalSemaphores[0]

    if vk.QueueSubmit(graphics_queue, 1, &submitInfo, inFlightFences[currentFrame]) != .SUCCESS {
        fmt.eprintln("failed to submit draw command buffer")
        os.exit(1)
    }

    presentInfo : vk.PresentInfoKHR
    presentInfo.sType = .PRESENT_INFO_KHR
    presentInfo.waitSemaphoreCount = 1
    presentInfo.pWaitSemaphores = &signalSemaphores[0]

    swapchains := [?]vk.SwapchainKHR{swapchain.handle}
    presentInfo.swapchainCount = 1
    presentInfo.pSwapchains = &swapchains[0]
    presentInfo.pImageIndices = &idx_ref
    presentInfo.pResults = nil 

    res := vk.QueuePresentKHR(present_queue, &presentInfo)
    if res == .ERROR_OUT_OF_DATE_KHR || res == .SUBOPTIMAL_KHR || framebufferResized{
        framebufferResized = false
        recreate_swapchain(r)
    } else if res != .SUCCESS {
        fmt.eprintln("failed to present swapchain image")
        os.exit(1)
    }
    
    r.currentFrame = (r.currentFrame + 1) % MAX_FRAMES_IN_FLIGHT
}