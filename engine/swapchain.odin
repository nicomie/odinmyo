package engine 

import sdl "vendor:sdl2"
import vk "vendor:vulkan"
import "core:fmt"
import "core:os"

SwapChainSupportDetails :: struct {
    capabilities: vk.SurfaceCapabilitiesKHR,
    formats: []vk.SurfaceFormatKHR,
    presentModes: []vk.PresentModeKHR,
}

SwapchainAttachments :: struct {
    views: []vk.ImageView,
    framebuffers: []vk.Framebuffer,
}

Swapchain :: struct {
    handle: vk.SwapchainKHR,
    imageCount: u32,
    images: []vk.Image,
    format: vk.Format,
    extent: vk.Extent2D,
    attachments: SwapchainAttachments,
}

querySwapChainSupport :: proc(target: vk.PhysicalDevice, ctx: ^Context) -> SwapChainSupportDetails{
    details: SwapChainSupportDetails
    surface := ctx.vulkan.surface
    
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

chooseSwapExtent :: proc(ctx: ^Context, capabilities: ^vk.SurfaceCapabilitiesKHR) -> vk.Extent2D {
    if capabilities.currentExtent.width != max(u32) {
        return capabilities.currentExtent
    } else {
    w,h : i32
    sdl.GL_GetDrawableSize(ctx.platform.window, &w, &h)
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

createSwapchain :: proc(ctx: ^Context) {
    physicalDevice := ctx.vulkan.physicalDevice
    device := ctx.vulkan.device
    queueIndices := &ctx.vulkan.queueIndices
    swapchain := &ctx.sc.swapchain

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
    createInfo.surface = ctx.vulkan.surface
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

    ctx.imagesInFlight = make([]vk.Fence, swapchain.imageCount)
    for i in 0..<swapchain.imageCount {
        ctx.imagesInFlight[i] = {}
    }
    ctx.renderFinishedSemaphores = make([]vk.Semaphore, swapchain.imageCount)

    semaphoreInfo: vk.SemaphoreCreateInfo
    semaphoreInfo.sType = .SEMAPHORE_CREATE_INFO

    for i in 0..<swapchain.imageCount {
        if vk.CreateSemaphore(device, &semaphoreInfo, nil, &ctx.renderFinishedSemaphores[i]) != .SUCCESS {
            fmt.eprintln("failed to create renderFinished semaphore")
            os.exit(1)
        }
    }

    swapchain.format = surfaceFormat.format 
    swapchain.extent = extent

}

recreateSwapchain :: proc(ctx: ^Context) {
    windowSurface := sdl.GetWindowSurface(ctx.platform.window)
    if (windowSurface.h == 0 || windowSurface.w == 0) {
        sdl.GetWindowSurface(ctx.platform.window)
    }
    vk.DeviceWaitIdle(ctx.vulkan.device)

    cleanSwapchain(ctx)

    createSwapchain(ctx)
    createImageViews(ctx)
    createColorResources(ctx)
    createDepthResource(ctx)
    createFramebuffer(ctx)

}

cleanSwapchain :: proc(ctx: ^Context) {   
    device := ctx.vulkan.device
    swapchain := &ctx.sc.swapchain
    depthImage := &ctx.sc.depthImage
    colorImage := &ctx.sc.colorImage
   
    for fb in swapchain.attachments.framebuffers do vk.DestroyFramebuffer(device, fb, nil)
    for view in swapchain.attachments.views do vk.DestroyImageView(device, view, nil)

    vk.DestroyImageView(device, colorImage.view, nil)
    vk.DestroyImage(device, colorImage.image.texture, nil)
    vk.FreeMemory(device, colorImage.image.memory, nil)

    vk.DestroyImageView(device, depthImage.view, nil)
    vk.DestroyImage(device, depthImage.image.texture, nil)
    vk.FreeMemory(device, depthImage.image.memory, nil)
  
    vk.DestroySwapchainKHR(device, swapchain.handle, nil)

}