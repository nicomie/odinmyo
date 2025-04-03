package main

import "core:fmt"
import "core:c"
import "core:os"
import "base:runtime"
import sdl "vendor:sdl2"
import vk "vendor:vulkan"
import "core:mem"
import "core:time"
import "core:strings"
import "core:slice"
import "core:math/linalg"
import "core:math"
import "core:encoding/endian"
import "core:c/libc"
import "vendor:stb/image"
import "vendor:cgltf"


USE_VALIDATION_LAYERS :: ODIN_DEBUG
WINDOW_WIDTH  :: 854
WINDOW_HEIGHT :: 480
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
MAX_FRAMES_IN_FLIGHT :: 2

Context :: struct {
    pipelines: map[string]vk.Pipeline, 

    uri: cstring,
    start : time.Time,
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
    meshPipelineLayout: vk.PipelineLayout,
    commandPool: vk.CommandPool,
    commandBuffers: [MAX_FRAMES_IN_FLIGHT]vk.CommandBuffer,
    imageAvailableSemaphores: [MAX_FRAMES_IN_FLIGHT]vk.Semaphore,
    renderFinishedSemaphores: [MAX_FRAMES_IN_FLIGHT]vk.Semaphore,
    inFlightFences: [MAX_FRAMES_IN_FLIGHT]vk.Fence,
    currentFrame :u32,
    framebufferResized :bool,

    uniformBuffers: []Buffer,
    uniformBuffersMapped: []rawptr,

    descriptorPool: vk.DescriptorPool,
    descriptorSetLayouts: map[string]vk.DescriptorSetLayout,
    descriptorSets: [2*MAX_FRAMES_IN_FLIGHT]vk.DescriptorSet,

    mipLevels: u32,
    texture: Image,
    textureImageView: vk.ImageView,
    textureSampler: vk.Sampler,

    depthImage: DepthImage,
    colorImage: DepthImage,
    msaa: vk.SampleCountFlags,
    camera: Camera,
    ray: Ray,
    meshes: [dynamic]MeshObject,

}

Camera :: struct {
    projection: linalg.Matrix4x4f32,
    position: linalg.Vector4f32,
    view: linalg.Matrix4x4f32,
    model: linalg.Matrix4x4f32
}

Ray :: struct {
    origin: linalg.Vector4f32,
    direction: linalg.Vector4f32,
 
}

MeshObject :: struct {
    vertexBuffer: Buffer, 
    indexBuffer: Buffer,
    transform: linalg.Matrix4x4f32,
}

DepthImage :: struct{
    image: Image,
    view: vk.ImageView

}

Image :: struct {
    texture: vk.Image,
    memory: vk.DeviceMemory,
}

Buffer :: struct
{
	buffer: vk.Buffer,
	memory: vk.DeviceMemory,
	length: int,
	size:   vk.DeviceSize,
}

Swapchain :: struct {
    handle: vk.SwapchainKHR,
    imageCount: u32,
    images: []vk.Image,
    format: vk.Format,
    extent: vk.Extent2D,
    imageViews: []vk.ImageView,
    framebuffers: []vk.Framebuffer,
}

QueueFamily :: enum {
    Graphics,
    Present,
}

Vec4Position :: proc(vec3: [3]f32) -> linalg.Vector4f32 {
    return linalg.Vector4f32{
        vec3[0], vec3[1], vec3[2], 1.0
    }
}

Vec4Direction:: proc(vec3: [3]f32) -> linalg.Vector4f32 {
    return linalg.Vector4f32{
        vec3[0], vec3[1], vec3[2], 0.0
    }
}

Vec3From4 :: proc(vec4: [4]f32) -> linalg.Vector3f32 {
    return linalg.Vector3f32{
        vec4[0], vec4[1], vec4[2]
    }
}


Vertex :: struct{
    pos: [3]f32,
    color: [3]f32,
    texCoord: [2]f32,
}

UBO :: struct{
    model: linalg.Matrix4f32,
    view: linalg.Matrix4f32,
    proj: linalg.Matrix4f32,
}

VERTEX_BINDING := vk.VertexInputBindingDescription{
    binding = 0,
    stride = size_of(Vertex),
    inputRate = .VERTEX,
}

VERTEX_ATTRIBUTES := [?]vk.VertexInputAttributeDescription{
	{
		binding = 0,
		location = 0,
		format = .R32G32B32_SFLOAT,
		offset = cast(u32)offset_of(Vertex, pos),
	},
	{
		binding = 0,
		location = 1,
		format = .R32G32B32_SFLOAT,
		offset = cast(u32)offset_of(Vertex, color),
	},
    {
		binding = 0,
		location = 2,
		format = .R32G32_SFLOAT,
		offset = cast(u32)offset_of(Vertex, texCoord),
	},
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
    appInfo.apiVersion = vk.API_VERSION_1_1

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

        if !features.fillModeNonSolid do return 0
        if !features.geometryShader do return 0
		if !checkDeviceExtensionSupport(dev) do return 0
        if !features.samplerAnisotropy do return 0

        details := querySwapChainSupport(dev, ctx)
        if len(details.formats) == 0 || len(details.presentModes) == 0 do return 0

        return score

    }

    hiscore := 0
    for dev in devices {
        score := suitability(ctx, dev)
        if score > hiscore {
            physicalDevice = dev
            msaa = getUsableSampleCount(physicalDevice)
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
    swapchain.imageViews = make([]vk.ImageView, len(swapchain.images))

    for _, i in swapchain.images {
        swapchain.imageViews[i] = createImageView(ctx, swapchain.images[i], swapchain.format, {.COLOR}, 1)
    }

}

createPipelines :: proc(using ctx: ^Context) {
    meshPipeline := createMeshPipeline(ctx)
    pipelines = make(map[string]vk.Pipeline)
    pipelines["mesh"] = meshPipeline

}

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


createMeshPipeline :: proc(using ctx: ^Context) -> vk.Pipeline {
    // Load shader modules
    vertShaderCode, _ := os.read_entire_file_from_filename("shaders/vert.spv")
    fragShaderCode, _ := os.read_entire_file_from_filename("shaders/frag.spv")
    defer delete(vertShaderCode)
    defer delete(fragShaderCode)

    vertShaderModule := createShaderModule(vertShaderCode, device)
    fragShaderModule := createShaderModule(fragShaderCode, device)
    defer vk.DestroyShaderModule(device, vertShaderModule, nil)
    defer vk.DestroyShaderModule(device, fragShaderModule, nil)

    // Shader stages
    vertShaderStage := vk.PipelineShaderStageCreateInfo{
        sType = .PIPELINE_SHADER_STAGE_CREATE_INFO,
        stage = {.VERTEX},
        module = vertShaderModule,
        pName = "main",
    }

    fragShaderStage := vk.PipelineShaderStageCreateInfo{
        sType = .PIPELINE_SHADER_STAGE_CREATE_INFO,
        stage = {.FRAGMENT},
        module = fragShaderModule,
        pName = "main",
    }

    shaderStages := []vk.PipelineShaderStageCreateInfo{vertShaderStage, fragShaderStage}


    vertexInput := vk.PipelineVertexInputStateCreateInfo{
        sType = .PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
        vertexBindingDescriptionCount = 1,
        pVertexBindingDescriptions = &VERTEX_BINDING,
        vertexAttributeDescriptionCount = cast(u32)len(VERTEX_ATTRIBUTES),
        pVertexAttributeDescriptions = &VERTEX_ATTRIBUTES[0],
    }

    // Input assembly
    inputAssembly := vk.PipelineInputAssemblyStateCreateInfo{
        sType = .PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
        topology = .TRIANGLE_LIST,
        primitiveRestartEnable = false,
    }

    // Viewport and scissor
    viewport := vk.Viewport{
        x = 0,
        y = 0,
        width = cast(f32)swapchain.extent.width,
        height = cast(f32)swapchain.extent.height,
        minDepth = 0,
        maxDepth = 1,
    }

    scissor := vk.Rect2D{
        offset = {0, 0},
        extent = swapchain.extent,
    }

    viewportState := vk.PipelineViewportStateCreateInfo{
        sType = .PIPELINE_VIEWPORT_STATE_CREATE_INFO,
        viewportCount = 1,
        pViewports = &viewport,
        scissorCount = 1,
        pScissors = &scissor,
    }

    // Rasterizer
    rasterizer := vk.PipelineRasterizationStateCreateInfo{
        sType = .PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
        depthClampEnable = false,
        rasterizerDiscardEnable = false,
        polygonMode = .FILL,
        lineWidth = 1.0,
        cullMode = {.BACK},
        frontFace = .COUNTER_CLOCKWISE,
        depthBiasEnable = false,
    }

    // Multisampling
    multisampling := vk.PipelineMultisampleStateCreateInfo{
        sType = .PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
        sampleShadingEnable = false,
        rasterizationSamples = msaa, 
    }

    // Depth and stencil testing
    depthStencil := vk.PipelineDepthStencilStateCreateInfo{
        sType = .PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO,
        depthTestEnable = true,
        depthWriteEnable = true,
        depthCompareOp = .LESS,
        depthBoundsTestEnable = false,
        stencilTestEnable = false,
    }

    // Color blending
    colorBlendAttachment := vk.PipelineColorBlendAttachmentState{
        colorWriteMask = {.R, .G, .B, .A},
        blendEnable = false,
    }

    colorBlending := vk.PipelineColorBlendStateCreateInfo{
        sType = .PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
        logicOpEnable = false,
        logicOp = .COPY,
        attachmentCount = 1,
        pAttachments = &colorBlendAttachment,
        blendConstants = {0, 0, 0, 0},
    }

    // Create the pipeline
    pipelineInfo := vk.GraphicsPipelineCreateInfo{
        sType = .GRAPHICS_PIPELINE_CREATE_INFO,
        stageCount = cast(u32)len(shaderStages),
        pStages = &shaderStages[0],
        pVertexInputState = &vertexInput,
        pInputAssemblyState = &inputAssembly,
        pViewportState = &viewportState,
        pRasterizationState = &rasterizer,
        pMultisampleState = &multisampling,
        pDepthStencilState = &depthStencil,
        pColorBlendState = &colorBlending,
        layout = meshPipelineLayout,
        renderPass = renderPass,
        subpass = 0,
    }

    pipeline: vk.Pipeline
    if vk.CreateGraphicsPipelines(device, 0, 1, &pipelineInfo, nil, &pipeline) != .SUCCESS {
        fmt.eprintln("failed to create mesh pipeline")
        os.exit(1)
    }

    return pipeline
}

createRenderPass :: proc(using ctx: ^Context) {
    colorAttachment := vk.AttachmentDescription{
        format = swapchain.format,
        samples = msaa,
        loadOp = .CLEAR ,
        storeOp = .STORE ,
        stencilLoadOp = .DONT_CARE,
        stencilStoreOp = .DONT_CARE,
        initialLayout = .UNDEFINED ,
        finalLayout = .COLOR_ATTACHMENT_OPTIMAL
    }

    colorAttachmentRef := vk.AttachmentReference{
        attachment = 0,
        layout = .COLOR_ATTACHMENT_OPTIMAL
    }

    colorAttachmentResolve := vk.AttachmentDescription{
        format = swapchain.format,
        samples = {._1},
        loadOp = .DONT_CARE,
        storeOp = .STORE,
        stencilLoadOp = .DONT_CARE,
        stencilStoreOp = .DONT_CARE,
        initialLayout = .UNDEFINED,
        finalLayout = .PRESENT_SRC_KHR
    }

    colorAttachmentResolveRef := vk.AttachmentReference{
        attachment = 2,
        layout = .COLOR_ATTACHMENT_OPTIMAL
    }

    depthAttachment := vk.AttachmentDescription{
        format = findDepthFormat(physicalDevice),
        samples = msaa,
        loadOp = .CLEAR,
        storeOp = .DONT_CARE,
        stencilLoadOp = .DONT_CARE,
        stencilStoreOp = .DONT_CARE,
        initialLayout = .UNDEFINED,
        finalLayout = .DEPTH_STENCIL_ATTACHMENT_OPTIMAL
    }
    
    depthAttachmentRef := vk.AttachmentReference{
        attachment = 1,
        layout = .DEPTH_STENCIL_ATTACHMENT_OPTIMAL,
    }

    subpass := vk.SubpassDescription{
        pipelineBindPoint = .GRAPHICS,
        colorAttachmentCount = 1,
        pColorAttachments = &colorAttachmentRef,
        pResolveAttachments = &colorAttachmentResolveRef,
        pDepthStencilAttachment = &depthAttachmentRef
    }

    dependency := vk.SubpassDependency{
        srcSubpass = vk.SUBPASS_EXTERNAL,
        dstSubpass = 0,
        srcStageMask = {.COLOR_ATTACHMENT_OUTPUT, .EARLY_FRAGMENT_TESTS},
        srcAccessMask = {},
        dstStageMask = {.COLOR_ATTACHMENT_OUTPUT, .EARLY_FRAGMENT_TESTS},
        dstAccessMask = {.COLOR_ATTACHMENT_WRITE, .DEPTH_STENCIL_ATTACHMENT_WRITE}
    }

    attachments := []vk.AttachmentDescription{colorAttachment, depthAttachment, colorAttachmentResolve}
    subpasses := []vk.SubpassDescription{subpass}
    dependencies := []vk.SubpassDependency{dependency }

    renderPassInfo := vk.RenderPassCreateInfo{
        sType = .RENDER_PASS_CREATE_INFO,
        attachmentCount = cast(u32)len(attachments),
        pAttachments = &attachments[0],
        subpassCount = cast(u32)len(subpasses),
        pSubpasses = &subpasses[0],
        dependencyCount = cast(u32)len(dependencies),
        pDependencies = &dependencies[0]
    }

    if vk.CreateRenderPass(device, &renderPassInfo, nil, &renderPass) != .SUCCESS {
        fmt.eprintln("failed to render pass")
        os.exit(1);
    }
}

createFrameBuffers :: proc(using ctx: ^Context) {
    swapchain.framebuffers = make([]vk.Framebuffer, len(swapchain.imageViews))

    for i in 0..<len(swapchain.imageViews) {
        attachments := []vk.ImageView{colorImage.view, depthImage.view, swapchain.imageViews[i]}
 
        framebufferInfo: vk.FramebufferCreateInfo
        framebufferInfo.sType = .FRAMEBUFFER_CREATE_INFO
        framebufferInfo.renderPass = renderPass 
        framebufferInfo.attachmentCount = cast(u32)len(attachments)
        framebufferInfo.pAttachments = &attachments[0]
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

    checkVk(vk.BeginCommandBuffer(buffer, &beginInfo))

    renderPassInfo: vk.RenderPassBeginInfo 
    renderPassInfo.sType = .RENDER_PASS_BEGIN_INFO
    renderPassInfo.renderPass = renderPass
    renderPassInfo.framebuffer = swapchain.framebuffers[imageIndex]
    renderPassInfo.renderArea.offset = {0, 0}
    renderPassInfo.renderArea.extent = swapchain.extent

    clearValues := []vk.ClearValue{
        {color = {float32 = [4]f32{0.0, 0.0, 0.0, 1.0}}}, 
        {depthStencil = {1.0, 0}}
    }
   
    renderPassInfo.clearValueCount = cast(u32)len(clearValues)
    renderPassInfo.pClearValues = &clearValues[0]
    
    vk.CmdBeginRenderPass(buffer, &renderPassInfo, .INLINE)

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

    vk.CmdBindPipeline(buffer, .GRAPHICS, pipelines["mesh"])
    for mesh in meshes {
        vertexBuffers := [?]vk.Buffer{mesh.vertexBuffer.buffer}
        offsets := [?]vk.DeviceSize{0}
        vk.CmdBindVertexBuffers(buffer, 0, 1, &vertexBuffers[0], &offsets[0])
        vk.CmdBindIndexBuffer(buffer, mesh.indexBuffer.buffer, 0, .UINT16)
        vk.CmdBindDescriptorSets(buffer, .GRAPHICS, meshPipelineLayout, 0, 1, &descriptorSets[currentFrame], 0, nil)
       vk.CmdDrawIndexed(buffer, cast(u32)mesh.indexBuffer.length, 1, 0, 0, 0)
    }


   
    vk.CmdEndRenderPass(buffer)

    checkVk(vk.EndCommandBuffer(buffer))

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

generateMipmaps :: proc(using ctx: ^Context, format: vk.Format, image: vk.Image, w,h: i32) {

    formatProperties : vk.FormatProperties
    vk.GetPhysicalDeviceFormatProperties(physicalDevice, format, &formatProperties)

    if (formatProperties.optimalTilingFeatures & vk.FormatFeatureFlags{vk.FormatFeatureFlag.SAMPLED_IMAGE_FILTER_LINEAR} == vk.FormatFeatureFlags{}) {
        fmt.eprintln("texture image format does not support linear blitting!")
        os.exit(1)
    }

    commandBuffer := beginCommand(ctx);
    defer endCommand(ctx, &commandBuffer)

    barrier := vk.ImageMemoryBarrier{
        sType = .IMAGE_MEMORY_BARRIER,
        image = image,
        srcQueueFamilyIndex = 0,
        dstQueueFamilyIndex = 0,
        subresourceRange = {
            aspectMask = {.COLOR},
            baseArrayLayer = 0,
            layerCount = 1,
            levelCount = 1
        }
    }

    mipW := w
    mipH := h
    for i in 1..<mipLevels {
        barrier.subresourceRange.baseMipLevel = i - 1
        barrier.oldLayout = .TRANSFER_DST_OPTIMAL
        barrier.newLayout = .TRANSFER_SRC_OPTIMAL
        barrier.srcAccessMask = {.TRANSFER_WRITE}
        barrier.dstAccessMask = {.TRANSFER_READ}

        vk.CmdPipelineBarrier(commandBuffer, {.TRANSFER}, {.TRANSFER}, {} , 0, nil, 0, nil, 1, &barrier)

        blit := vk.ImageBlit{
            srcOffsets = [2]vk.Offset3D{
                {0,0,0},
                {mipW, mipH, 1}
            },
            srcSubresource = {
                aspectMask = {.COLOR},
                mipLevel = i - 1,
                baseArrayLayer = 0,
                layerCount = 1,
            },
            dstOffsets =  [2]vk.Offset3D{
                {0, 0, 0},
                {mipW > 1 ? mipW/2 : 1, mipH > 1 ? mipH/2 : 1, 1}
            },
            dstSubresource = {
                aspectMask = {.COLOR},
                mipLevel = i,
                baseArrayLayer = 0,
                layerCount = 1
            }
        }

        vk.CmdBlitImage(commandBuffer, image, .TRANSFER_SRC_OPTIMAL, image, .TRANSFER_DST_OPTIMAL, 1, &blit, .LINEAR)

        barrier.oldLayout = .TRANSFER_SRC_OPTIMAL
        barrier.newLayout = .SHADER_READ_ONLY_OPTIMAL
        barrier.srcAccessMask = {.TRANSFER_READ}
        barrier.dstAccessMask = {.SHADER_READ}

        vk.CmdPipelineBarrier(commandBuffer, {.TRANSFER}, {.FRAGMENT_SHADER}, {}, 0, nil, 0, nil, 1, &barrier)

        if mipW > 1 do mipW /= 2
        if mipH> 1 do mipH /=2
    }

    barrier.subresourceRange.baseMipLevel = mipLevels -1
    barrier.oldLayout = .TRANSFER_DST_OPTIMAL
    barrier.newLayout = .SHADER_READ_ONLY_OPTIMAL
    barrier.srcAccessMask = {.TRANSFER_WRITE}
    barrier.dstAccessMask = {.SHADER_READ}

    vk.CmdPipelineBarrier(commandBuffer, {.TRANSFER}, {.FRAGMENT_SHADER}, {}, 0, nil, 0, nil, 1, &barrier)
}


createTextureImage :: proc(using ctx: ^Context) {

    f := libc.fopen(uri, "rb")
    if f == nil {
        fmt.eprintf("failed to fopen file \n", uri)
        os.exit(1)
    }
    defer libc.fclose(f)

    w, h, channels: i32 
    
    loadedImage := image.load_from_file(f, &w, &h, &channels, 4); defer image.image_free(loadedImage)

    max :=  w > h ? h : w
    mipLevels = cast(u32)math.floor_f32(math.log2(cast(f32)max)) + 1

    if loadedImage == nil {
        fmt.eprintln("failed to load image via load_from_file")
        os.exit(1)
    }
    w32 := cast(u32)w
    h32 := cast(u32)h

    imageSize := cast(vk.DeviceSize)(w32 * h32 * 4)
    stagingBuffer : Buffer 
    createBuffer(ctx, imageSize, {.TRANSFER_SRC}, {.HOST_VISIBLE, .HOST_COHERENT}, &stagingBuffer)

    data: rawptr
    vk.MapMemory(device, stagingBuffer.memory, 0, imageSize, {}, &data)
    mem.copy(data, loadedImage, cast(int)imageSize)
    vk.UnmapMemory(device, stagingBuffer.memory)

 
    createImage(ctx, w32, h32, mipLevels, {._1}, .R8G8B8A8_SRGB, .OPTIMAL, {.TRANSFER_SRC, .TRANSFER_DST, .SAMPLED}, {.DEVICE_LOCAL}, &texture)
    transitionImageLayout(ctx, texture.texture, .R8G8B8A8_SRGB, .UNDEFINED, .TRANSFER_DST_OPTIMAL, mipLevels)
    copyBufferToImage(ctx, stagingBuffer.buffer, w32, h32)

    vk.DestroyBuffer(device, stagingBuffer.buffer, nil)
    vk.FreeMemory(device, stagingBuffer.memory, nil)

    generateMipmaps(ctx, .R8G8B8A8_SRGB, texture.texture, w, h)

}

beginCommand :: proc(using ctx:^Context) -> vk.CommandBuffer{
    allocInfo := vk.CommandBufferAllocateInfo{
        sType = .COMMAND_BUFFER_ALLOCATE_INFO,
        level = .PRIMARY,
        commandPool = commandPool,
        commandBufferCount = 1
    }

    cmdBuffer : vk.CommandBuffer
    vk.AllocateCommandBuffers(device, &allocInfo, &cmdBuffer)

    beginInfo := vk.CommandBufferBeginInfo{
        sType = .COMMAND_BUFFER_BEGIN_INFO,
        flags = {.ONE_TIME_SUBMIT}
    }

    vk.BeginCommandBuffer(cmdBuffer, &beginInfo)
    return cmdBuffer
}

endCommand :: proc(using ctx: ^Context, cmdBuffer: ^vk.CommandBuffer) {
    vk.EndCommandBuffer(cmdBuffer^)

    submitInfo := vk.SubmitInfo{
        sType = .SUBMIT_INFO,
        commandBufferCount = 1,
        pCommandBuffers = &cmdBuffer^
    }

    vk.QueueSubmit(graphicsQueue, 1, &submitInfo, {})
    vk.QueueWaitIdle(graphicsQueue)
    vk.FreeCommandBuffers(device, commandPool, 1, &cmdBuffer^)
}

transitionImageLayout :: proc(using ctx: ^Context, image: vk.Image, format: vk.Format, oldLayout,newLayout: vk.ImageLayout, mips: u32) {
    cmdBuffer := beginCommand(ctx)
    defer endCommand(ctx, &cmdBuffer)

    barrier : vk.ImageMemoryBarrier
    barrier.sType = .IMAGE_MEMORY_BARRIER
    barrier.oldLayout = oldLayout
    barrier.newLayout = newLayout
    barrier.image = image
    barrier.srcQueueFamilyIndex = 0;
    barrier.dstQueueFamilyIndex = 0;
    barrier.subresourceRange.aspectMask = {.COLOR}
    barrier.subresourceRange.baseMipLevel = 0
    barrier.subresourceRange.levelCount = mips
    barrier.subresourceRange.baseArrayLayer = 0
    barrier.subresourceRange.layerCount = 1
    barrier.srcAccessMask = {}
    barrier.dstAccessMask = {}

    sourceStage : vk.PipelineStageFlags 
    destinationStage : vk.PipelineStageFlags
    if oldLayout == .UNDEFINED && newLayout == .TRANSFER_DST_OPTIMAL {
        barrier.srcAccessMask = {}
        barrier.dstAccessMask = {.TRANSFER_WRITE}

        sourceStage = {.TOP_OF_PIPE}
        destinationStage = {.TRANSFER}
    } else if oldLayout == .TRANSFER_DST_OPTIMAL && newLayout == .SHADER_READ_ONLY_OPTIMAL {
        barrier.srcAccessMask = {.TRANSFER_WRITE}
        barrier.dstAccessMask = {.SHADER_READ}

        sourceStage = {.TRANSFER}
        destinationStage = {.FRAGMENT_SHADER}
    } else {
        fmt.eprintln("unsupported layout transition")
        os.exit(1)
    }

    vk.CmdPipelineBarrier(cmdBuffer, sourceStage, destinationStage, {}, 0, nil, 0, nil, 1, &barrier)
}

copyBufferToImage :: proc(using ctx: ^Context, buffer: vk.Buffer, w,h : u32) {
    cmdBuffer := beginCommand(ctx)
    defer endCommand(ctx, &cmdBuffer)

    region : vk.BufferImageCopy
    region.bufferOffset = 0
    region.bufferRowLength = 0
    region.bufferImageHeight = 0
    region.imageSubresource.aspectMask = {.COLOR}
    region.imageSubresource.mipLevel = 0
    region.imageSubresource.baseArrayLayer = 0
    region.imageSubresource.layerCount = 1
    region.imageOffset = {0,0,0}
    region.imageExtent = {w,h,1}

    vk.CmdCopyBufferToImage(cmdBuffer, buffer, texture.texture, .TRANSFER_DST_OPTIMAL, 1, &region)
    }


createImage :: proc(using ctx: ^Context, w,h,mips : u32, numSamples: vk.SampleCountFlags, format: vk.Format, tiling: vk.ImageTiling, 
    usage: vk.ImageUsageFlags, properties: vk.MemoryPropertyFlags, image: ^Image) {
    
        imageInfo := vk.ImageCreateInfo{
            sType = .IMAGE_CREATE_INFO,
            imageType = .D2,
            extent = {
                width = w,
                height = h,
                depth = 1,
            },
            mipLevels = mips,
            arrayLayers = 1,
            format = format,
            tiling = tiling,
            initialLayout = .UNDEFINED,
            usage = usage,
            sharingMode = .EXCLUSIVE,
            samples = numSamples,
            flags = {}
        }
    
        if vk.CreateImage(device, &imageInfo, nil, &image.texture) != .SUCCESS {
            fmt.eprintln("failed to CreateImage")
            os.exit(1)
        }
    
        memReq : vk.MemoryRequirements 
        vk.GetImageMemoryRequirements(device, image.texture, &memReq)
    
        allocInfo := vk.MemoryAllocateInfo{
            sType = .MEMORY_ALLOCATE_INFO,
            allocationSize = memReq.size,
            memoryTypeIndex = findMemType(physicalDevice, memReq.memoryTypeBits, {.DEVICE_LOCAL})
        }
    
        if vk.AllocateMemory(device, &allocInfo, nil, &image.memory) != .SUCCESS {
            fmt.eprintln("failed to AllocateMemory or image")
            os.exit(1)
        }
    
        vk.BindImageMemory(device, image.texture, image.memory, 0)
        
    }

    createTextureImageView :: proc(using ctx: ^Context) {    
        textureImageView = createImageView(ctx, texture.texture, .R8G8B8A8_SRGB, {.COLOR}, mipLevels)
    }

    createImageView :: proc(using ctx: ^Context, image: vk.Image, format: vk.Format, aspectFlags: vk.ImageAspectFlags, mips: u32
    ) -> vk.ImageView {
        viewInfo := vk.ImageViewCreateInfo{
            sType = .IMAGE_VIEW_CREATE_INFO,
            image = image,
            viewType = .D2,
            format = format,
            subresourceRange = {
                aspectMask = aspectFlags,
                baseMipLevel = 0,
                levelCount = mips,
                baseArrayLayer = 0,
                layerCount = 1, 
            }
        }
        imageView: vk.ImageView
        if vk.CreateImageView(device, &viewInfo, nil, &imageView) != .SUCCESS {
            fmt.eprintln("failed to CreateImageView")
            os.exit(1)
        }
        return imageView
    }

    createTextureSampler ::proc(using ctx:^Context) {

        properties: vk.PhysicalDeviceProperties
        vk.GetPhysicalDeviceProperties(physicalDevice, &properties)

        samplerInfo := vk.SamplerCreateInfo{
            sType = .SAMPLER_CREATE_INFO,
            magFilter = .LINEAR, 
            minFilter = .LINEAR,
            addressModeU = .REPEAT,
            addressModeV = .REPEAT,
            addressModeW = .REPEAT,
            anisotropyEnable = true,
            maxAnisotropy = properties.limits.maxSamplerAnisotropy,
            borderColor = .INT_OPAQUE_BLACK,
            unnormalizedCoordinates = false,
            compareEnable = false,
            compareOp = .ALWAYS,
            mipmapMode = .LINEAR,
            minLod =  0.0,
            maxLod = f32(mipLevels),
            mipLodBias = 0.0,
        }

        if vk.CreateSampler(device, &samplerInfo, nil, &textureSampler) != .SUCCESS {
            fmt.eprintln("failed to CreateSampler")
            os.exit(1)
        }
    }

    findDepthFormat :: proc(physicalDevice: vk.PhysicalDevice) -> vk.Format {
        return findSupportedFormat(
            physicalDevice, 
            {.D32_SFLOAT, .D32_SFLOAT_S8_UINT, .D24_UNORM_S8_UINT},
            .OPTIMAL,
            {.DEPTH_STENCIL_ATTACHMENT}
        )
    }

    hasStencilComponent :: proc(format: vk.Format) -> bool{
        return format == .D32_SFLOAT_S8_UINT || format == .D24_UNORM_S8_UINT
    }

    findSupportedFormat :: proc(physicalDevice: vk.PhysicalDevice, candidates: []vk.Format, 
        tiling: vk.ImageTiling, features: vk.FormatFeatureFlags) -> vk.Format{

            for &format in candidates {
                props: vk.FormatProperties
                vk.GetPhysicalDeviceFormatProperties(physicalDevice, format, &props)
    
                if tiling == .LINEAR && (props.linearTilingFeatures & features) == features {
                    return format
                } else if tiling == .OPTIMAL && (props.optimalTilingFeatures & features) == features {
                    return format
                }
            }
           
            fmt.eprintln("failed to find supported format")
            os.exit(1)
    }

    createDepthResource ::proc(using ctx: ^Context) {
        depthFormat := findDepthFormat(physicalDevice)
        createImage(ctx, swapchain.extent.width, swapchain.extent.height, 1, msaa, depthFormat, 
        .OPTIMAL, {.DEPTH_STENCIL_ATTACHMENT}, {.DEVICE_LOCAL}, &depthImage.image)
        depthImage.view = createImageView(ctx, depthImage.image.texture, depthFormat, {.DEPTH}, 1)
    }

    Primitive :: struct {
        firstIndex: u32,
        indexCount: u32,
    }

    Mesh :: struct {
        primitives: []Primitive
    }

    Material :: struct {
        baseColorFactor: [4]f32,
        baseColorTextureIndex: u32
    }

    loadTextures :: proc(using ctx: ^Context, data: ^cgltf.data) {
        s := [?]string{"textures/", string(data.images[0].uri)}
        uri = strings.clone_to_cstring(strings.concatenate(s[:]))
    }

    extractVertexColor :: proc(data: ^cgltf.data) {
        for mesh in data.meshes {
            for primitive in mesh.primitives {
                for attribute in primitive.attributes {
                    if attribute.type == cgltf.attribute_type.color {
                        accessor := attribute.data;
        
    
                        for i in 0..<accessor.count {
                            color: [4]f32;
                            res:=cgltf.accessor_read_float(accessor, i, &color[0], 4);
                            fmt.printf("Vertex Color: R=%f G=%f B=%f A=%f\n", color[0], color[1], color[2], color[3]);
                        }
                    }
                }
            }
        }
    }

    loadGlbModel :: proc(using ctx: ^Context) -> ([]Vertex, []u16) {
        // Parse the gltf file
        data, res := cgltf.parse_file({}, "glbs/BoxTextured.gltf");
        if res != .success {
            fmt.eprintf("Failed to parse_file: %v\n", res);
            os.exit(1);
        }

        result := cgltf.load_buffers({}, data, "glbs/BoxTextured.gltf")
        if result != .success {
            fmt.eprintf("Failed to load_buffers: %v\n", result)
        }

        if validationRes := cgltf.validate(data); validationRes != .success {
            fmt.eprintf("Failed to validate: %v\n", validationRes)

        }

        vertices: [dynamic]Vertex;
        indices: [dynamic]u16 ;

        if data == nil || len(data.meshes) == 0 {
            return vertices[:], indices[:]
        }

        loadTextures(ctx, data)
    
        for mesh in data.meshes {
            for primitive in mesh.primitives {
             
                // Process vertex positions
                for i in 0..<len(primitive.attributes) {
                    attribute := primitive.attributes[i]
                    accessor := attribute.data
                
                    // Read position data
                    if attribute.type == .position {
                        for j in 0..<accessor.count {
                            position := [3]f32{} 
                            res := cgltf.accessor_read_float(accessor, j, &position[0], 3)
                            if res == false do fmt.eprintln("pos")
                            append(&vertices, Vertex{pos=position})
                        }
                    }
                    // Read texcoord data
                    if attribute.type == .texcoord {
                        for j in 0..<accessor.count {
                            texcoord := [2]f32{}; 
                            res := cgltf.accessor_read_float(accessor, j, &texcoord[0], 2);
                            if res == false {
                                fmt.eprintln("Failed to read texcoord at index: ", j);
                            }
                            vertices[j].texCoord = texcoord; 
                            vertices[j].color = {1.0, 1.0, 1.0}; 
                        }
                    }            
                }
        
           // Extract indices
           if primitive.indices != nil {
               index_accessor := primitive.indices;
               for i in 0..<index_accessor.count {
                   idx := cgltf.accessor_read_index(index_accessor, i);
                   append(&indices, cast(u16)idx);
               }
           }
       }
    }

    extractVertexColor(data)
    fmt.println("after extraction")
    fmt.println(len(vertices))
    fmt.println(len(indices))

    cgltf.free(data)

    return vertices[:], indices[:]
}

getUsableSampleCount :: proc(physicalDevice: vk.PhysicalDevice) -> vk.SampleCountFlags {
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

createColorResources :: proc(using ctx: ^Context) {
    colorFormat := swapchain.format

    createImage(ctx, swapchain.extent.width, swapchain.extent.height, 1, msaa, colorFormat,
    .OPTIMAL, {.TRANSIENT_ATTACHMENT, .COLOR_ATTACHMENT}, {.DEVICE_LOCAL}, &colorImage.image)

    colorImage.view = createImageView(ctx, colorImage.image.texture, colorFormat, {.COLOR}, 1)
}
    
setupGlb :: proc(using ctx: ^Context) {
    v, i := loadGlbModel(ctx)
    vBuffer: Buffer
    iBuffer: Buffer

    vBuffer = createVertexBuffer(ctx, v)
    iBuffer = createIndexBuffer(ctx, i)

    append(&meshes, MeshObject{
        vertexBuffer = vBuffer,
        indexBuffer = iBuffer,
        transform = linalg.MATRIX4F32_IDENTITY,
    })

}

createDescriptorSetLayouts :: proc(using ctx: ^Context) {
    meshDescriptorSetLayout := createDescriptorSetLayout(device, []DescriptorSetLayout{
        {binding = 0, type = .UNIFORM_BUFFER, shaderStageFlags = {.VERTEX}}, 
        {binding = 1, type = .COMBINED_IMAGE_SAMPLER, shaderStageFlags = {.FRAGMENT}}, 
    })

    descriptorSetLayouts = make(map[string]vk.DescriptorSetLayout)
    descriptorSetLayouts["mesh"] = meshDescriptorSetLayout
}

createPipelineLayouts :: proc(using ctx: ^Context) {
    pipelineLayoutInfo := vk.PipelineLayoutCreateInfo{
        sType = .PIPELINE_LAYOUT_CREATE_INFO,
        setLayoutCount = 1,
        pSetLayouts = &descriptorSetLayouts["mesh"],
        pushConstantRangeCount = 0,
    }

    if vk.CreatePipelineLayout(device, &pipelineLayoutInfo, nil, &meshPipelineLayout) != .SUCCESS {
        fmt.eprintln("failed to create pipeline layout")
        os.exit(1)
    }
}

initVulkan :: proc(using ctx: ^Context, vertices: []Vertex, indices: []u16) {
    start = time.now()
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

    createDescriptorSetLayouts(ctx)
    createPipelineLayouts(ctx)
    createCommandPool(ctx)

    createPipelines(ctx)
    setupGlb(ctx)

    createColorResources(ctx)
    createDepthResource(ctx)
    createFrameBuffers(ctx)
    createTextureImage(ctx)
    createTextureImageView(ctx)
    createTextureSampler(ctx)
    createUniformBuffers(ctx)
    createCommandBuffers(ctx)
    createDescriptorPool(ctx)
    createDescriptorSets(ctx)
    createSyncObjects(ctx)

}

exit :: proc(using ctx: ^Context) {
    cleanSwapchain(ctx)
    
    vk.DestroySampler(device, textureSampler, nil)
    vk.DestroyImageView(device, textureImageView, nil)
    vk.DestroyImage(device, texture.texture, nil)
    vk.FreeMemory(device, texture.memory, nil)

    for i in 0..<MAX_FRAMES_IN_FLIGHT {
        vk.DestroyBuffer(device, uniformBuffers[i].buffer, nil)
        vk.FreeMemory(device,  uniformBuffers[i].memory, nil)
    }

    vk.DestroyDescriptorPool(device, descriptorPool, nil)
    vk.DestroyDescriptorSetLayout(device, descriptorSetLayouts["mesh"], nil)
    delete(descriptorSetLayouts)
    
    for mesh in meshes {
        vk.DestroyBuffer(device, mesh.vertexBuffer.buffer, nil)
        vk.FreeMemory(device,  mesh.vertexBuffer.memory, nil)
        vk.DestroyBuffer(device, mesh.indexBuffer.buffer, nil)
        vk.FreeMemory(device,  mesh.indexBuffer.memory, nil)
    }

    for _, pipeline in pipelines {
        vk.DestroyPipeline(device, pipeline, nil)
    }
    delete(pipelines)

    vk.DestroyPipelineLayout(device, meshPipelineLayout, nil)

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


createDescriptorSetLayout :: proc(device: vk.Device, descriptorSets: []DescriptorSetLayout) -> vk.DescriptorSetLayout{

    bindings := make([]vk.DescriptorSetLayoutBinding, len(descriptorSets))
    for set, i in descriptorSets {
        bindings[i] = vk.DescriptorSetLayoutBinding{
            binding = set.binding,
            descriptorCount = 1,
            descriptorType = set.type,
            stageFlags = set.shaderStageFlags,
            pImmutableSamplers = nil,
        }
    }
         
    layoutInfo := vk.DescriptorSetLayoutCreateInfo{
        sType = .DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
        bindingCount = cast(u32)len(bindings),
        pBindings = &bindings[0]
    }
    
    layout: vk.DescriptorSetLayout
    if vk.CreateDescriptorSetLayout(device, &layoutInfo, nil, &layout) != .SUCCESS {
        fmt.eprintln("failed to CreateDescriptorSetLayout")
        os.exit(1)
    }

    return layout
}

DescriptorSetLayout :: struct {
    binding: u32,
    type: vk.DescriptorType,
    shaderStageFlags: vk.ShaderStageFlags
}

createDescriptorSets :: proc(using ctx: ^Context) {
    meshLayouts := make([]vk.DescriptorSetLayout, MAX_FRAMES_IN_FLIGHT)
    for i in 0..<MAX_FRAMES_IN_FLIGHT {
        meshLayouts[i] = descriptorSetLayouts["mesh"]
    }

    meshAllocInfo := vk.DescriptorSetAllocateInfo{
        sType = .DESCRIPTOR_SET_ALLOCATE_INFO,
        descriptorPool = descriptorPool,
        descriptorSetCount = MAX_FRAMES_IN_FLIGHT,
        pSetLayouts = &meshLayouts[0],
    }

    meshDescriptorSets := make([]vk.DescriptorSetLayout, MAX_FRAMES_IN_FLIGHT)
    if vk.AllocateDescriptorSets(device, &meshAllocInfo, &descriptorSets[0]) != .SUCCESS {
        fmt.eprintln("failed to allocate mesh descriptor sets")
        os.exit(1)
    }

    // Update descriptor sets for the mesh pipeline
    for i in 0..<MAX_FRAMES_IN_FLIGHT {
        bufferInfo := vk.DescriptorBufferInfo{
            buffer = uniformBuffers[i].buffer,
            offset = 0,
            range = size_of(UBO),
        }

        imageInfo := vk.DescriptorImageInfo{
            imageLayout = .SHADER_READ_ONLY_OPTIMAL,
            imageView = textureImageView,
            sampler = textureSampler,
        }

        meshDescriptorWrites := []vk.WriteDescriptorSet{
            {
                sType = .WRITE_DESCRIPTOR_SET,
                dstSet = descriptorSets[i],
                dstBinding = 0,
                dstArrayElement = 0,
                descriptorType = .UNIFORM_BUFFER,
                descriptorCount = 1,
                pBufferInfo = &bufferInfo,
            },
            {
                sType = .WRITE_DESCRIPTOR_SET,
                dstSet = descriptorSets[i],
                dstBinding = 1,
                dstArrayElement = 0,
                descriptorType = .COMBINED_IMAGE_SAMPLER,
                descriptorCount = 1,
                pImageInfo = &imageInfo,
            },
        }

        vk.UpdateDescriptorSets(device, cast(u32)len(meshDescriptorWrites), &meshDescriptorWrites[0], 0, nil)
    }
}

createDescriptorPool :: proc(using ctx: ^Context) {

    poolSizes := []vk.DescriptorPoolSize{
        {
            type = .UNIFORM_BUFFER,
            descriptorCount = MAX_FRAMES_IN_FLIGHT*2
        },
        {
            type = .COMBINED_IMAGE_SAMPLER,
            descriptorCount = MAX_FRAMES_IN_FLIGHT
        }
    }

    poolInfo : vk.DescriptorPoolCreateInfo
    poolInfo.sType = .DESCRIPTOR_POOL_CREATE_INFO
    poolInfo.poolSizeCount = cast(u32)len(poolSizes)
    poolInfo.pPoolSizes = &poolSizes[0]
    poolInfo.maxSets = MAX_FRAMES_IN_FLIGHT*2
    
    if vk.CreateDescriptorPool(device, &poolInfo, nil, &descriptorPool) != .SUCCESS {
        fmt.eprintln("failed to CreateDescriptorPool")
        os.exit(1)
    }

}

createUniformBuffers :: proc(using ctx: ^Context) {
    bufferSize := cast(vk.DeviceSize)size_of(UBO)

    uniformBuffers = make([]Buffer, MAX_FRAMES_IN_FLIGHT)
    uniformBuffersMapped = make([]rawptr, MAX_FRAMES_IN_FLIGHT)

    for i in 0..<MAX_FRAMES_IN_FLIGHT {
        createBuffer(ctx, bufferSize, {.UNIFORM_BUFFER}, {.HOST_VISIBLE, .HOST_COHERENT}, &uniformBuffers[i])
        vk.MapMemory(device, uniformBuffers[i].memory, 0, bufferSize, {}, &uniformBuffersMapped[i])
    }
}

createBuffer :: proc(
    using ctx: ^Context, 
    bufferSize: vk.DeviceSize, 
    usage: vk.BufferUsageFlags, 
    properties: vk.MemoryPropertyFlags, 
    buffer: ^Buffer,
    data: rawptr = nil
) {
    
    bufferInfo := vk.BufferCreateInfo{
        sType = .BUFFER_CREATE_INFO,
        size = bufferSize,
        usage = usage,
        sharingMode = .EXCLUSIVE,
    }
    checkVk(vk.CreateBuffer(device, &bufferInfo, nil, &buffer.buffer))

    memRequirements: vk.MemoryRequirements
    vk.GetBufferMemoryRequirements(device, buffer.buffer, &memRequirements)

    allocInfo := vk.MemoryAllocateInfo{
        sType = .MEMORY_ALLOCATE_INFO,
        allocationSize = memRequirements.size,
        memoryTypeIndex = findMemType(physicalDevice, memRequirements.memoryTypeBits, properties)
    }

    checkVk(vk.AllocateMemory(device, &allocInfo, nil, &buffer.memory))
    checkVk(vk.BindBufferMemory(device, buffer.buffer, buffer.memory, 0))

    if data != nil {
        ptr: rawptr
        checkVk(vk.MapMemory(device, buffer.memory, 0, bufferSize, {}, &ptr))
        mem.copy(ptr, data, int(bufferSize))
        vk.UnmapMemory(device, buffer.memory)
    }
}

checkVk :: proc(result: vk.Result, location := #caller_location) {
    if result != .SUCCESS {
        fmt.eprintf("Vulkan error at %s: %v\n", location, result)
        os.exit(1)
    }
}

findMemType :: proc(physicalDevice: vk.PhysicalDevice, typeFilter: u32, props: vk.MemoryPropertyFlags) -> u32{
    memProps : vk.PhysicalDeviceMemoryProperties
    vk.GetPhysicalDeviceMemoryProperties(physicalDevice, &memProps)

    for i in 0..<memProps.memoryTypeCount {
        if ((typeFilter & (1 << i) != 0) && (memProps.memoryTypes[i].propertyFlags & props) == props) {
            return i
        }
    }

    fmt.eprintln("failed to find suitable memory type")
    os.exit(1)
}

copyBuffer :: proc(using ctx: ^Context, src, dst: Buffer, size: vk.DeviceSize) {
    cmdBuffer := beginCommand(ctx)
    defer endCommand(ctx, &cmdBuffer)
    copyRegion := vk.BufferCopy{
        srcOffset = 0,
        dstOffset = 0,
        size = size,
    }
    vk.CmdCopyBuffer(cmdBuffer, src.buffer, dst.buffer, 1, &copyRegion)
}

createVertexBuffer :: proc(using ctx: ^Context, vertices: []Vertex) -> Buffer {
    buffer: Buffer
    buffer.length = len(vertices)
    buffer.size = cast(vk.DeviceSize)(len(vertices) * size_of(Vertex))
    
    staging: Buffer 
    createBuffer(ctx, buffer.size, {.TRANSFER_SRC}, {.HOST_VISIBLE, .HOST_COHERENT}, &staging, raw_data(vertices))
    
    createBuffer(ctx, buffer.size, {.VERTEX_BUFFER, .TRANSFER_DST}, {.DEVICE_LOCAL}, &buffer)
    copyBuffer(ctx, staging, buffer, buffer.size)

    return buffer
}

createIndexBuffer :: proc(using ctx: ^Context, indices: []u16) -> Buffer{
    buffer: Buffer
    buffer.length = len(indices)
    buffer.size = cast(vk.DeviceSize)(len(indices) * size_of(indices[0]))

    staging: Buffer 
    createBuffer(ctx, buffer.size, {.TRANSFER_SRC}, {.HOST_VISIBLE, .HOST_COHERENT}, &staging)

    data: rawptr 
    vk.MapMemory(device, staging.memory, 0, buffer.size, {}, &data)
    mem.copy(data, raw_data(indices), cast(int)buffer.size)
    vk.UnmapMemory(device, staging.memory)

    createBuffer(ctx ,buffer.size, {.TRANSFER_DST, .INDEX_BUFFER}, {.DEVICE_LOCAL}, &buffer)
    copyBuffer(ctx, staging, buffer, buffer.size)

    vk.DestroyBuffer(device, staging.buffer, nil)
    vk.FreeMemory(device, staging.memory, nil)

    return buffer
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
    createColorResources(ctx)
    createDepthResource(ctx)
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

    updateUniformBuffer(ctx, currentFrame)

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

updateUniformBuffer :: proc(using ctx: ^Context, currentImage: u32) {
 
    current := time.now()
    timeElapsed := cast(f32)time.duration_seconds(time.diff(start, current))
    movement := math.sin(timeElapsed)
    speed := f32(1.0)
    movement *= speed
    translation := linalg.matrix4_translate(linalg.Vector3f32{movement, 0, 0})
    ubo: UBO
    angle := math.to_radians_f32(90) * timeElapsed
    axis := linalg.Vector3f32{0, 0, 1}
    ubo.model = translation * linalg.matrix4_rotate(angle, axis)
    ubo.view = linalg.matrix4_look_at_f32(
        linalg.Vector3f32{5, 5, 5}, 
        linalg.Vector3f32{0, 0, 0}, 
        linalg.Vector3f32{0, 0, 1}, true)
    ubo.proj = linalg.matrix4_perspective(
        math.to_radians_f32(60.0),
         cast(f32)swapchain.extent.width / cast(f32)swapchain.extent.height, 
         0.1, 
         1000.0,
         true
        )
    ubo.proj[1][1] *= -1
    camera.projection = ubo.proj
    camera.position = linalg.Vector4f32{5, 5, 5, 1}
    camera.view = ubo.view
    camera.model = ubo.model 
    mem.copy(uniformBuffersMapped[currentImage], &ubo, size_of(ubo));
}

cleanSwapchain :: proc(using ctx: ^Context) {   
    vk.DestroyImageView(device, colorImage.view, nil)
    vk.DestroyImage(device, colorImage.image.texture, nil)
    vk.FreeMemory(device, colorImage.image.memory, nil)

    vk.DestroyImageView(device, depthImage.view, nil)
    vk.DestroyImage(device, depthImage.image.texture, nil)
    vk.FreeMemory(device, depthImage.image.memory, nil)

    for fb in swapchain.framebuffers do vk.DestroyFramebuffer(device, fb, nil)
    for view in swapchain.imageViews do vk.DestroyImageView(device, view, nil)
    vk.DestroySwapchainKHR(device, swapchain.handle, nil)

}

main :: proc() {


    vertices := [?]Vertex{
        {{-0.5, -0.5, 0.0}, {1.0, 0.0, 0.0}, {0.0, 0.0}},
        {{0.5, -0.5, 0.0}, {0.0, 1.0, 0.0}, {1.0, 0.0}},
        {{0.5, 0.5, 0.0}, {0.0, 0.0, 1.0}, {1.0, 1.0}},
        {{-0.5, 0.5, 0.0}, {1.0, 1.0, 1.0}, {0.0, 1.0}},

        {{-0.5, -0.5, -0.5}, {1.0, 0.0, 0.0}, {0.0, 0.0}},
        {{0.5, -0.5, -0.5}, {0.0, 1.0, 0.0}, {1.0, 0.0}},
        {{0.5, 0.5, -0.5}, {0.0, 0.0, 1.0}, {1.0, 1.0}},
        {{-0.5, 0.5, -0.5}, {1.0, 1.0, 1.0}, {0.0, 1.0}}
    }

    indices := [?]u16{
        0,1,2,2,3,0,
        4,5,6,6,7,4
    }

    using ctx: Context
    initWindow(&ctx)
    for &q in queueIndices do q = -1
    initVulkan(&ctx, vertices[:], indices[:])
    defer exit(&ctx);

    run(&ctx);
   
}