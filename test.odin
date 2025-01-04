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
MAX_FRAMES_IN_FLIGHT :: 2

Context :: struct {
    window: ^sdl.Window,
    instance: vk.Instance,
    debugMessenger: vk.DebugUtilsMessengerEXT,
    physicalDevice: vk.PhysicalDevice,
    device: vk.Device,
    queueIndices: [QueueFamily]int,
    graphicsQueue: vk.Queue,
    surface: vk.SurfaceKHR,
    presentQueue: vk.Queue,
    swapchain: Swapchain,
    renderPass: vk.RenderPass,
    pipelineLayout: vk.PipelineLayout,
    graphicsPipeline: vk.Pipeline,
    commandPool: vk.CommandPool,
    commandBuffers: [MAX_FRAMES_IN_FLIGHT]vk.CommandBuffer,
    imageAvailableSemaphores: [MAX_FRAMES_IN_FLIGHT]vk.Semaphore,
    renderFinishedSemaphores: [MAX_FRAMES_IN_FLIGHT]vk.Semaphore,
    inFlightFences: [MAX_FRAMES_IN_FLIGHT]vk.Fence,
    currentFrame :u32,
    framebufferResized :bool,
}

Swapchain :: struct {
    handle: vk.SwapchainKHR,
    imageCount: u32,
    images: []vk.Image,
    format: vk.Format,
    extent: vk.Extent2D,
    imageViews: []vk.ImageView,
    framebuffers: []vk.Framebuffer
}

QueueFamily :: enum {
    Graphics,
    Present,
}

Vertex :: struct{
    pos: [2]f32,
    color: [3]f32,
}

getBindingDescription :: proc(vertex: Vertex) -> VertexInputRate{
    bindingDescription : vk.VertexInputBindingDescription 
    bindingDescription.binding = 0
    bindingDescription.stride = sizeof(Vertex)
    bindingDescription.inputRate = .VERTEX
    return bindingDescription
}

getAttributeDescriptions :: proc(vertex: Vertex) -> [2]vk.VertexInputAttributeDescription {
    attributeDescriptions : vk.VertexInputAttributeDescription 
    attributeDescriptions[0].binding = 0
    attributeDescriptions[0].location = 0
    attributeDescriptions[0].format = .R32G32_SFLOAT
    attributeDescriptions[0].offset = offsetof(Vertex, pos)
    attributeDescriptions[1]
    return attributeDescriptions
}

initWindow :: proc (ctx: ^Context) {
    if sdl.Init(sdl.INIT_VIDEO) != 0 {
        fmt.eprintln("sdl_Init failed: ", sdl.GetError())
        return
    }

    // Create window
    window := sdl.CreateWindow("Odin sdl2 Wayland Demo", sdl.WINDOWPOS_UNDEFINED, 
    sdl.WINDOWPOS_UNDEFINED, WINDOW_WIDTH, WINDOW_HEIGHT, {.VULKAN, .RESIZABLE})

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
 
    suitability :: proc(using ctx: ^Context, dev: vk.PhysicalDevice) -> int {
        props: vk.PhysicalDeviceProperties 
        features: vk.PhysicalDeviceFeatures
        vk.GetPhysicalDeviceProperties(dev, &props)
        vk.GetPhysicalDeviceFeatures(dev, &features)

        score := 0
        if props.deviceType == .DISCRETE_GPU do score += 1000
        score += cast(int)props.limits.maxImageDimension2D

        if !features.geometryShader do return 0;
		if !checkDeviceExtensionSupport(dev) do return 0;

        details := querySwapChainSupport(dev, ctx)
        if len(details.formats) == 0 || len(details.presentModes) == 0 do return 0

        return score

    }

    hiscore := 0
    for dev in devices {
        score := suitability(ctx, dev)
        if score > hiscore {
            physicalDevice = dev
            hiscore = score
        }
    }

    if hiscore == 0 {
        fmt.println("failed to find a suitable GPU!");
        os.exit(1)

    }
}

createLogicalDevice :: proc(using ctx: ^Context) {
    findQueueFamilies(ctx)

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

    vk.GetDeviceQueue(device, u32(queueIndices[.Graphics]), 0, &graphicsQueue);
    vk.GetDeviceQueue(device, u32(queueIndices[.Present]), 0, &presentQueue);

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

findQueueFamilies :: proc(using ctx: ^Context) {
    count: u32;
    vk.GetPhysicalDeviceQueueFamilyProperties(physicalDevice, &count, nil)

    families:= make([]vk.QueueFamilyProperties, count);
    vk.GetPhysicalDeviceQueueFamilyProperties(physicalDevice, &count, raw_data(families))
 
    for family, i in families {
        if .GRAPHICS in family.queueFlags && queueIndices[.Graphics] == -1 do queueIndices[.Graphics] = i

        presentSupport : b32 = false
        vk.GetPhysicalDeviceSurfaceSupportKHR(physicalDevice, u32(i), surface, &presentSupport)
        if presentSupport && queueIndices[.Present] == -1 do queueIndices[.Present] = i

        for q in queueIndices do if q == -1 do continue
    }

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

createSwapchain :: proc(using ctx: ^Context) {
    swapChainSupport := querySwapChainSupport(physicalDevice, ctx)

    surfaceFormat := chooseSwapSurfaceFormat(&swapChainSupport.formats)
    presentMode := chooseSwapPresentMode(&swapChainSupport.presentModes)
    extent := chooseSwapExtent(ctx, &swapChainSupport.capabilities)
    swapchain.imageCount = swapChainSupport.capabilities.minImageCount + 1

    if swapChainSupport.capabilities.maxImageCount > 0 && 
    swapchain.imageCount > swapChainSupport.capabilities.maxImageCount {
        swapchain.imageCount = swapChainSupport.capabilities.maxImageCount
    }

    createInfo: vk.SwapchainCreateInfoKHR
    createInfo.sType = .SWAPCHAIN_CREATE_INFO_KHR
    createInfo.surface = surface
    createInfo.minImageCount = swapchain.imageCount;
    createInfo.imageFormat = surfaceFormat.format;
    createInfo.imageColorSpace = surfaceFormat.colorSpace;
    createInfo.imageExtent = extent;
    createInfo.imageArrayLayers = 1;
    createInfo.imageUsage = {.COLOR_ATTACHMENT};

    queueFamilyIndices := [len(QueueFamily)]u32{cast(u32)queueIndices[.Graphics], cast(u32)queueIndices[.Present]} 

    if queueIndices[.Graphics] != queueIndices[.Present] {
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

    if vk.CreateSwapchainKHR(device, &createInfo, nil, &swapchain.handle) != .SUCCESS {
        fmt.eprintln("failed to create swapchain")
        os.exit(1);
    }

    vk.GetSwapchainImagesKHR(device, swapchain.handle, &swapchain.imageCount, nil);
	swapchain.images = make([]vk.Image, swapchain.imageCount)
	vk.GetSwapchainImagesKHR(device, swapchain.handle, &swapchain.imageCount, raw_data(swapchain.images));

    swapchain.format = surfaceFormat.format 
    swapchain.extent = extent

}

createImageViews :: proc(using ctx: ^Context) {
    using ctx.swapchain
    imageViews = make([]vk.ImageView, len(images))

    for _, i in images {
        createInfo: vk.ImageViewCreateInfo
        createInfo.sType = .IMAGE_VIEW_CREATE_INFO
        createInfo.image = images[i]
        createInfo.viewType = .D2
        createInfo.format = format
        createInfo.components.r = .IDENTITY
        createInfo.components.g = .IDENTITY
        createInfo.components.b = .IDENTITY
        createInfo.components.a = .IDENTITY
        createInfo.subresourceRange.aspectMask = {.COLOR}
        createInfo.subresourceRange.baseMipLevel = 0
        createInfo.subresourceRange.levelCount = 1
        createInfo.subresourceRange.baseArrayLayer = 0
        createInfo.subresourceRange.layerCount = 1

        if vk.CreateImageView(device, &createInfo, nil, &imageViews[i]) != .SUCCESS {
            fmt.eprintf("Failed to create image views for index %d \n", i)
            os.exit(1)
        }
    }

}

createGraphicsPipeline :: proc(using ctx: ^Context) {

    createShaderModule :: proc(data: []u8, device: vk.Device) -> vk.ShaderModule {
        createInfo : vk.ShaderModuleCreateInfo
        createInfo.sType = .SHADER_MODULE_CREATE_INFO
        createInfo.codeSize = len(data)
        createInfo.pCode = cast(^u32)raw_data(data)

        shaderModule : vk.ShaderModule
        if vk.CreateShaderModule(device, &createInfo, nil, &shaderModule) != .SUCCESS {
            fmt.println("failed to create shader module")
            os.exit(1) 
        }

        return shaderModule
    }

    vert, ok := os.read_entire_file_from_filename("shaders/vert.spv")
    if !ok {
        return
    }
    defer delete(vert)
    frag :[]u8
    frag,ok = os.read_entire_file_from_filename("shaders/frag.spv")
    if !ok {
        return
    }
    defer delete(frag)

    vModule := createShaderModule(vert, device)
    fModule := createShaderModule(frag, device)

    defer vk.DestroyShaderModule(device, vModule, nil)
    defer vk.DestroyShaderModule(device, fModule, nil)

    dynamicStates := [?]vk.DynamicState{.VIEWPORT, .SCISSOR};
    dynamicState : vk.PipelineDynamicStateCreateInfo
    dynamicState.sType = .PIPELINE_DYNAMIC_STATE_CREATE_INFO
    dynamicState.dynamicStateCount = len(dynamicStates)
    dynamicState.pDynamicStates = &dynamicStates[0]

    vertShaderStageInfo: vk.PipelineShaderStageCreateInfo
    vertShaderStageInfo.sType = .PIPELINE_SHADER_STAGE_CREATE_INFO
    vertShaderStageInfo.stage = {.VERTEX}
    vertShaderStageInfo.module = vModule 
    vertShaderStageInfo.pName = "main"

    fragShaderStageInfo: vk.PipelineShaderStageCreateInfo
    fragShaderStageInfo.sType = .PIPELINE_SHADER_STAGE_CREATE_INFO
    fragShaderStageInfo.stage = {.FRAGMENT}
    fragShaderStageInfo.module = fModule 
    fragShaderStageInfo.pName = "main"

    shaderStages :  = []vk.PipelineShaderStageCreateInfo{vertShaderStageInfo, fragShaderStageInfo}

    vertexInputInfo : vk.PipelineVertexInputStateCreateInfo
    vertexInputInfo.sType = .PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO
    vertexInputInfo.vertexBindingDescriptionCount = 0.0
    vertexInputInfo.pVertexBindingDescriptions = nil
    vertexInputInfo.vertexAttributeDescriptionCount = 0.0
    vertexInputInfo.pVertexAttributeDescriptions = nil

    inputAssembly: vk.PipelineInputAssemblyStateCreateInfo
    inputAssembly.sType = .PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO
    inputAssembly.topology = .TRIANGLE_LIST
    inputAssembly.primitiveRestartEnable = false
    
    viewport : vk.Viewport
    viewport.x = 0.0
    viewport.y = 0.0
    viewport.width = cast(f32)swapchain.extent.width
    viewport.height = cast(f32)swapchain.extent.height
    viewport.minDepth = 0.0
    viewport.maxDepth = 1.0

    scissor: vk.Rect2D
    scissor.offset = {0, 0}
    scissor.extent = {0, 0}

    viewportState: vk.PipelineViewportStateCreateInfo
    viewportState.sType = .PIPELINE_VIEWPORT_STATE_CREATE_INFO
    viewportState.viewportCount = 1.0
    viewportState.pViewports = &viewport
    viewportState.scissorCount = 1.0
    viewportState.pScissors = &scissor

    rasterizer: vk.PipelineRasterizationStateCreateInfo
    rasterizer.sType = .PIPELINE_RASTERIZATION_STATE_CREATE_INFO
    rasterizer.depthClampEnable = false 
    rasterizer.rasterizerDiscardEnable = false
    rasterizer.polygonMode = .FILL 
    rasterizer.lineWidth = 1.0
    rasterizer.cullMode = {.BACK}
    rasterizer.frontFace = .CLOCKWISE 
    rasterizer.depthBiasEnable = false 
    rasterizer.depthBiasConstantFactor = 0.0
    rasterizer.depthBiasClamp = 0.0 
    rasterizer.depthBiasSlopeFactor = 0.0 

    multisampling: vk.PipelineMultisampleStateCreateInfo
    multisampling.sType = .PIPELINE_MULTISAMPLE_STATE_CREATE_INFO
    multisampling.sampleShadingEnable = false
    multisampling.rasterizationSamples = {._1}
    multisampling.minSampleShading = 1.0
    multisampling.pSampleMask = nil 
    multisampling.alphaToCoverageEnable = false 
    multisampling.alphaToOneEnable = false 

    colorBlendAttachments: vk.PipelineColorBlendAttachmentState
    colorBlendAttachments.colorWriteMask = {.R, .G, .B, .A}
    colorBlendAttachments.blendEnable = false 
    colorBlendAttachments.srcColorBlendFactor = .ONE
    colorBlendAttachments.dstColorBlendFactor = .ZERO
    colorBlendAttachments.colorBlendOp = .ADD 
    colorBlendAttachments.srcAlphaBlendFactor = .ONE 
    colorBlendAttachments.dstAlphaBlendFactor = .ZERO 
    colorBlendAttachments.alphaBlendOp = .ADD

    colorBlending: vk.PipelineColorBlendStateCreateInfo 
    colorBlending.sType = .PIPELINE_COLOR_BLEND_STATE_CREATE_INFO
    colorBlending.logicOpEnable = false 
    colorBlending.logicOp = .COPY 
    colorBlending.attachmentCount = 1
    colorBlending.pAttachments = &colorBlendAttachments
    colorBlending.blendConstants[0] = 0.0
    colorBlending.blendConstants[1] = 0.0
    colorBlending.blendConstants[2] = 0.0
    colorBlending.blendConstants[3] = 0.0

    pipelineLayoutInfo: vk.PipelineLayoutCreateInfo 
    pipelineLayoutInfo.sType = .PIPELINE_LAYOUT_CREATE_INFO
    pipelineLayoutInfo.setLayoutCount = 0 
    pipelineLayoutInfo.pSetLayouts = nil
    pipelineLayoutInfo.pushConstantRangeCount = 0 
    pipelineLayoutInfo.pPushConstantRanges = nil 

    if vk.CreatePipelineLayout(device, &pipelineLayoutInfo, nil, &pipelineLayout) != .SUCCESS {
        fmt.println("failed to pipeline layout")
        os.exit(1) 
    }

    pipelineInfo : vk.GraphicsPipelineCreateInfo
    pipelineInfo.sType = .GRAPHICS_PIPELINE_CREATE_INFO
    pipelineInfo.stageCount = 2
    pipelineInfo.pStages = &shaderStages[0]
    pipelineInfo.pVertexInputState = &vertexInputInfo
    pipelineInfo.pInputAssemblyState = &inputAssembly
    pipelineInfo.pViewportState = &viewportState
    pipelineInfo.pRasterizationState = &rasterizer 
    pipelineInfo.pMultisampleState = &multisampling
    pipelineInfo.pDepthStencilState = nil
    pipelineInfo.pColorBlendState = &colorBlending
    pipelineInfo.pDynamicState = &dynamicState
    pipelineInfo.layout = pipelineLayout
    pipelineInfo.renderPass = renderPass 
    pipelineInfo.subpass = 0
    pipelineInfo.basePipelineHandle = vk.Pipeline{}
    pipelineInfo.basePipelineIndex = -1

    if vk.CreateGraphicsPipelines(device, 0, 1, &pipelineInfo, nil, &graphicsPipeline) != .SUCCESS {
        fmt.println("failed to pipeline")
        os.exit(1) 
    }

}

createRenderPass :: proc(using ctx: ^Context) {
    colorAttachment: vk.AttachmentDescription
    colorAttachment.format = swapchain.format
    colorAttachment.samples = {._1}
    colorAttachment.loadOp = .CLEAR 
    colorAttachment.storeOp = .STORE 
    colorAttachment.stencilLoadOp = .DONT_CARE
    colorAttachment.stencilStoreOp = .DONT_CARE
    colorAttachment.initialLayout = .UNDEFINED 
    colorAttachment.finalLayout = .PRESENT_SRC_KHR

    colorAttachmentRef: vk.AttachmentReference
    colorAttachmentRef.attachment = 0
    colorAttachmentRef.layout = .COLOR_ATTACHMENT_OPTIMAL

    subpass : vk.SubpassDescription
    subpass.pipelineBindPoint = .GRAPHICS
    subpass.colorAttachmentCount = 1
    subpass.pColorAttachments = &colorAttachmentRef

    dependency: vk.SubpassDependency
    dependency.srcSubpass = vk.SUBPASS_EXTERNAL
    dependency.dstSubpass = 0
    dependency.srcStageMask = {.COLOR_ATTACHMENT_OUTPUT}
    dependency.srcAccessMask = {}
    dependency.dstStageMask = {.COLOR_ATTACHMENT_OUTPUT}
    dependency.dstAccessMask = {.COLOR_ATTACHMENT_WRITE}
    

    renderPassInfo : vk.RenderPassCreateInfo
    renderPassInfo.sType = .RENDER_PASS_CREATE_INFO
    renderPassInfo.attachmentCount = 1
    renderPassInfo.pAttachments = &colorAttachment
    renderPassInfo.subpassCount = 1
    renderPassInfo.pSubpasses = &subpass
    renderPassInfo.dependencyCount = 1
    renderPassInfo.pDependencies = &dependency

    if vk.CreateRenderPass(device, &renderPassInfo, nil, &renderPass) != .SUCCESS {
        fmt.eprintln("failed to render pass")
        os.exit(1);
    }

}

createFrameBuffers :: proc(using ctx: ^Context) {
    swapchain.framebuffers = make([]vk.Framebuffer, len(swapchain.imageViews))

    for i in 0..<len(swapchain.imageViews) {
        attachments := swapchain.imageViews[i]

        framebufferInfo: vk.FramebufferCreateInfo
        framebufferInfo.sType = .FRAMEBUFFER_CREATE_INFO
        framebufferInfo.renderPass = renderPass 
        framebufferInfo.attachmentCount = 1
        framebufferInfo.pAttachments = &attachments 
        framebufferInfo.width = swapchain.extent.width
        framebufferInfo.height = swapchain.extent.height
        framebufferInfo.layers = 1

        if vk.CreateFramebuffer(device, &framebufferInfo, nil, &swapchain.framebuffers[i]) != .SUCCESS{
            fmt.eprintf("Failed to create fram buffer for index %d \n", i)
            os.exit(1)
        }
    }
}

createCommandPool :: proc(using ctx: ^Context) {
    poolInfo : vk.CommandPoolCreateInfo
    poolInfo.sType = .COMMAND_POOL_CREATE_INFO 
    poolInfo.flags = {.RESET_COMMAND_BUFFER}
    poolInfo.queueFamilyIndex = u32(queueIndices[.Graphics])

    if vk.CreateCommandPool(device, &poolInfo, nil, &commandPool) != .SUCCESS {
        fmt.eprintln("failed to create command pool")
        os.exit(1)
    }
}

createCommandBuffers :: proc(using ctx: ^Context) {
    allocInfo: vk.CommandBufferAllocateInfo
    allocInfo.sType = .COMMAND_BUFFER_ALLOCATE_INFO
    allocInfo.commandPool = commandPool 
    allocInfo.level = .PRIMARY
    allocInfo.commandBufferCount = MAX_FRAMES_IN_FLIGHT

    if vk.AllocateCommandBuffers(device, &allocInfo, &commandBuffers[0]) != .SUCCESS {
        fmt.eprintln("failed to create command buffer")
        os.exit(1)
    }
}

recordCommandBuffer :: proc(using ctx: ^Context, buffer: vk.CommandBuffer, imageIndex: u32) {
    beginInfo: vk.CommandBufferBeginInfo
    beginInfo.sType = .COMMAND_BUFFER_BEGIN_INFO
    beginInfo.pInheritanceInfo = nil

    if vk.BeginCommandBuffer(buffer, &beginInfo) != .SUCCESS {
        fmt.eprintln("failed to begin to record command buffer")
        os.exit(1)
    }

    renderPassInfo: vk.RenderPassBeginInfo 
    renderPassInfo.sType = .RENDER_PASS_BEGIN_INFO
    renderPassInfo.renderPass = renderPass
    renderPassInfo.framebuffer = swapchain.framebuffers[imageIndex]
    renderPassInfo.renderArea.offset = {0, 0}
    renderPassInfo.renderArea.extent = swapchain.extent

    clearColor : vk.ClearValue
    clearColor.color.float32 = [4]f32{0.0, 0.0, 0.0, 1.0}
    renderPassInfo.clearValueCount = 1
    renderPassInfo.pClearValues = &clearColor
    
    vk.CmdBeginRenderPass(buffer, &renderPassInfo, .INLINE)
    vk.CmdBindPipeline(buffer, .GRAPHICS, graphicsPipeline)

    viewport : vk.Viewport
    viewport.x = 0.0
    viewport.y = 0.0
    viewport.width = cast(f32)swapchain.extent.width
    viewport.height = cast(f32)swapchain.extent.height
    viewport.minDepth = 0.0
    viewport.maxDepth = 1.0
    vk.CmdSetViewport(buffer, 0, 1, &viewport)

    scissor : vk.Rect2D 
    scissor.offset = {0, 0}
    scissor.extent = swapchain.extent
    vk.CmdSetScissor(buffer, 0, 1, &scissor)

    vk.CmdDraw(buffer, 3, 1, 0, 0)
    vk.CmdEndRenderPass(buffer)

    if vk.EndCommandBuffer(buffer) != .SUCCESS {
        fmt.eprintln("failed to record command buffer")
        os.exit(1)
    }

}

createSyncObjects :: proc(using ctx: ^Context) {
    semaphoreInfo: vk.SemaphoreCreateInfo
    semaphoreInfo.sType = .SEMAPHORE_CREATE_INFO

    fenceInfo: vk.FenceCreateInfo
    fenceInfo.sType = .FENCE_CREATE_INFO
    fenceInfo.flags = {.SIGNALED}

    for i in 0..<MAX_FRAMES_IN_FLIGHT {
        if vk.CreateSemaphore(device, &semaphoreInfo, nil, &imageAvailableSemaphores[i]) != .SUCCESS ||
        vk.CreateSemaphore(device, &semaphoreInfo, nil, &renderFinishedSemaphores[i]) != .SUCCESS ||
        vk.CreateFence(device, &fenceInfo, nil, &inFlightFences[i]) != .SUCCESS {
            fmt.eprintln("failed to create semaphores")
            os.exit(1)
        }
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
    createSwapchain(ctx)
    createImageViews(ctx)
    findQueueFamilies(ctx)
    createRenderPass(ctx)
    createGraphicsPipeline(ctx)
    createFrameBuffers(ctx)
    createCommandPool(ctx)
    createCommandBuffers(ctx)
    createSyncObjects(ctx)

}

recreateSwapchain :: proc(using ctx: ^Context) {
    windowSurface := sdl.GetWindowSurface(window)
    if (windowSurface.h == 0 || windowSurface.w == 0) {
        sdl.GetWindowSurface(window)
    }
    vk.DeviceWaitIdle(device)

    cleanSwapchain(ctx)

    createSwapchain(ctx)
    createImageViews(ctx)
    createFrameBuffers(ctx)

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
         drawFrame(ctx)
    }

    vk.DeviceWaitIdle(device)
}

drawFrame :: proc(using ctx: ^Context) {
    vk.WaitForFences(device, 1, &inFlightFences[currentFrame], true, max(u64))
    vk.ResetFences(device, 1, &inFlightFences[currentFrame])

    imageIndex: u32
    res := vk.AcquireNextImageKHR(device, swapchain.handle, max(u64), imageAvailableSemaphores[currentFrame], {}, &imageIndex)
    if res == .ERROR_OUT_OF_DATE_KHR {
        recreateSwapchain(ctx)
        return
    } else if res != .SUCCESS && res != .SUBOPTIMAL_KHR {
        fmt.eprintln("failed to acquire swapchain image")
        os.exit(1)
    }

    vk.ResetFences(device, 1, &inFlightFences[currentFrame])

    vk.ResetCommandBuffer(commandBuffers[currentFrame], {})
    recordCommandBuffer(ctx, commandBuffers[currentFrame], imageIndex)

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

    if vk.QueueSubmit(graphicsQueue, 1, &submitInfo, inFlightFences[currentFrame]) != .SUCCESS {
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
    presentInfo.pImageIndices = &imageIndex 
    presentInfo.pResults = nil 

    res = vk.QueuePresentKHR(presentQueue, &presentInfo)
    if res == .ERROR_OUT_OF_DATE_KHR || res == .SUBOPTIMAL_KHR || framebufferResized{
        framebufferResized = false
        recreateSwapchain(ctx)
    } else if res != .SUCCESS {
        fmt.eprintln("failed to present swapchain image")
        os.exit(1)
    }

    currentFrame = (currentFrame + 1) & MAX_FRAMES_IN_FLIGHT

}

cleanSwapchain :: proc(using ctx: ^Context) {
    for fb in swapchain.framebuffers do vk.DestroyFramebuffer(device, fb, nil)
    for view in swapchain.imageViews do vk.DestroyImageView(device, view, nil)
    vk.DestroySwapchainKHR(device, swapchain.handle, nil)

}

exit :: proc(using ctx: ^Context) {
    cleanSwapchain(ctx)   

    vk.DestroyPipeline(device, graphicsPipeline, nil)
    vk.DestroyPipelineLayout(device, pipelineLayout, nil)
    vk.DestroyRenderPass(device, renderPass, nil)

    for i in 0..<MAX_FRAMES_IN_FLIGHT {
        vk.DestroySemaphore(device, imageAvailableSemaphores[i], nil);
        vk.DestroySemaphore(device, renderFinishedSemaphores[i], nil);
        vk.DestroyFence(device, inFlightFences[i], nil);
    }
   
    vk.DestroyCommandPool(device, commandPool, nil)   
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

    vertices := [?]Vertex{
        {{0.0, -0.5}, {1.0, 0.0, 0.0}},
        {{0.5, 0.5}, {0.0, 1.0, 0.0}},
        {{-0.5, 0.5}, {0.0, 0.0, 1.0}},
    }

    using ctx: Context
    initWindow(&ctx)
    for &q in queueIndices do q = -1
    initVulkan(&ctx)
    defer exit(&ctx);

    run(&ctx);
   
}