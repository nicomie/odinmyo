package app

import "core:fmt"
import "core:os"
import vk "vendor:vulkan"
import sdl "vendor:sdl2"


Swapchain :: struct {
    handle: vk.SwapchainKHR,
    imageCount: u32,
    images: []vk.Image,
    format: vk.Format,
    extent: vk.Extent2D,
    imageViews: []vk.ImageView,
    framebuffers: []vk.Framebuffer,
}

SwapchainSupportDetails :: struct {
    capabilities: vk.SurfaceCapabilitiesKHR,
    formats: []vk.SurfaceFormatKHR,
    presentModes: []vk.PresentModeKHR,
}

recreate_swapchain :: proc(using r: ^Renderer) {
    windowSurface := sdl.GetWindowSurface(window)
    if (windowSurface.h == 0 || windowSurface.w == 0) {
        sdl.GetWindowSurface(window)
    }
    vk.DeviceWaitIdle(device)

    // clean_swapchain(ctx)

    create_swapchain(r)
    create_image_views(r)
    create_color_resource(r)
    create_depth_resource(r)
    create_framebuffer(r)
}

query_swapchain_support :: proc(target: vk.PhysicalDevice, using r: ^Renderer) -> SwapchainSupportDetails{
    details: SwapchainSupportDetails
    
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

choose_swap_surface_format :: proc(availableFormats: ^[]vk.SurfaceFormatKHR) -> vk.SurfaceFormatKHR {
    for format in availableFormats {
        if format.format == .B8G8R8A8_SRGB && format.colorSpace == .SRGB_NONLINEAR {
            return format
        } 
    }
    
    return availableFormats[0]
}

choose_swap_present_mode :: proc(modes: ^[]vk.PresentModeKHR) -> vk.PresentModeKHR {
    for mode in modes {
        if mode == .MAILBOX do return mode
    }
    return .FIFO
}

choose_swap_extent :: proc(r: ^Renderer, capabilities: ^vk.SurfaceCapabilitiesKHR) -> vk.Extent2D {
   if capabilities.currentExtent.width != max(u32) {
        return capabilities.currentExtent
   } else {
    w,h : i32
    sdl.GL_GetDrawableSize(r.window, &w, &h)
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

create_swapchain :: proc(using r: ^Renderer) {
    swapChainSupport := query_swapchain_support(physicalDevice, r)

    surfaceFormat := choose_swap_surface_format(&swapChainSupport.formats)
    presentMode := choose_swap_present_mode(&swapChainSupport.presentModes)
    extent := choose_swap_extent(r, &swapChainSupport.capabilities)
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

init_swapchain :: proc(r: ^Renderer) -> bool {
    create_swapchain(r)
    create_image_views(r)
    return true
}