package engine

import vk "vendor:vulkan"
import "core:fmt"
import "core:os"

QueueFamily :: enum {
    Graphics,
    Present,
}

hasStencilComponent :: proc(format: vk.Format) -> bool{
    return format == .D32_SFLOAT_S8_UINT || format == .D24_UNORM_S8_UINT
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

findDepthFormat :: proc(physicalDevice: vk.PhysicalDevice) -> vk.Format {
    return findSupportedFormat(
        physicalDevice, 
        {.D32_SFLOAT, .D32_SFLOAT_S8_UINT, .D24_UNORM_S8_UINT},
        .OPTIMAL,
        {.DEPTH_STENCIL_ATTACHMENT}
    )
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