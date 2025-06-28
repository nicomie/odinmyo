package engine

import sdl "vendor:sdl2"
import vk "vendor:vulkan"
import "core:fmt"
import "core:os"

createColorResources :: proc(using ctx: ^Context) {
    colorFormat := swapchain.format

    createImage(ctx, swapchain.extent.width, swapchain.extent.height, 1, {._1}, colorFormat,
    .OPTIMAL, {.TRANSIENT_ATTACHMENT, .COLOR_ATTACHMENT}, {.DEVICE_LOCAL}, &colorImage.image)

    colorImage.view = createImageView(ctx, colorImage.image.texture, colorFormat, {.COLOR}, 1, "color")
}

createDepthResource ::proc(using ctx: ^Context) {
    depthFormat := findDepthFormat(physicalDevice)
    createImage(ctx, swapchain.extent.width, swapchain.extent.height, 1, {._1}, depthFormat, 
    .OPTIMAL, {.DEPTH_STENCIL_ATTACHMENT}, {.DEVICE_LOCAL}, &depthImage.image)
    depthImage.view = createImageView(ctx, depthImage.image.texture, depthFormat, {.DEPTH}, 1, "depth")
}

createIdResource :: proc(using ctx: ^Context) {
    
    createImage(
        ctx,
        swapchain.extent.width,
        swapchain.extent.height,
        1,
        {._1},                         
        .R8G8B8A8_UNORM,
        .OPTIMAL,
        {.COLOR_ATTACHMENT, .TRANSFER_SRC}, 
        {.DEVICE_LOCAL},
        &idImage.image
    )
    
    idImage.view = createImageView(
        ctx,
        idImage.image.texture,
        .R8G8B8A8_UNORM,
        {.COLOR},
        1,
        "id"
    )

    cmdBuffer := beginCommand(ctx)
    
    barrier := vk.ImageMemoryBarrier{
        sType = .IMAGE_MEMORY_BARRIER,
        oldLayout = .UNDEFINED,
        newLayout = .COLOR_ATTACHMENT_OPTIMAL,
        srcQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
        dstQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
        image = idImage.image.texture,
        subresourceRange = {
            aspectMask = {.COLOR},
            baseMipLevel = 0,
            levelCount = 1,
            baseArrayLayer = 0,
            layerCount = 1
        },
        srcAccessMask = {},
        dstAccessMask = {.COLOR_ATTACHMENT_WRITE}
    }

    vk.CmdPipelineBarrier(
        cmdBuffer,
        {.TOP_OF_PIPE},
        {.COLOR_ATTACHMENT_OUTPUT},
        {},
        0, nil,
        0, nil,
        1, &barrier
    )

    endCommand(ctx, &cmdBuffer)
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

createSurface :: proc(using ctx: ^Context) {
    if sdl.Vulkan_CreateSurface(window, instance, &surface) != true {
        fmt.println("failed to create window surface")
        return 
    }
}