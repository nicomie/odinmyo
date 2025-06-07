package app

import vk "vendor:vulkan"
import "core:fmt"
import "core:os"


DepthImage :: struct{
    image: Image,
    view: vk.ImageView
}

Image :: struct {
    texture: vk.Image,
    memory: vk.DeviceMemory,
}

create_image :: proc(using r: ^Renderer, w,h,mips : u32, numSamples: vk.SampleCountFlags, format: vk.Format, tiling: vk.ImageTiling, 
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
            memoryTypeIndex = find_mem_type(physicalDevice, memReq.memoryTypeBits, {.DEVICE_LOCAL})
        }
    
        if vk.AllocateMemory(device, &allocInfo, nil, &image.memory) != .SUCCESS {
            fmt.eprintln("failed to AllocateMemory or image")
            os.exit(1)
        }
    
    vk.BindImageMemory(device, image.texture, image.memory, 0)
}

create_image_view :: proc(using r: ^Renderer, image: vk.Image, format: vk.Format, aspectFlags: vk.ImageAspectFlags, mips: u32
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

create_image_views :: proc(using r: ^Renderer) {
    swapchain.imageViews = make([]vk.ImageView, len(swapchain.images))

    for _, i in swapchain.images {
        swapchain.imageViews[i] = create_image_view(r, swapchain.images[i], swapchain.format, {.COLOR}, 1)
    }
}

transition_image_layout :: proc(using r: ^Renderer, image: vk.Image, format: vk.Format, oldLayout,newLayout: vk.ImageLayout, mips: u32) {
    cmdBuffer,err := begin_command(r)
    defer end_command(r, &cmdBuffer)

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

generate_mipmaps :: proc(using r: ^Renderer, format: vk.Format, image: vk.Image, w,h: i32) {

    mipLevels := u32(1)
    formatProperties : vk.FormatProperties
    vk.GetPhysicalDeviceFormatProperties(physicalDevice, format, &formatProperties)

    if (formatProperties.optimalTilingFeatures & vk.FormatFeatureFlags{vk.FormatFeatureFlag.SAMPLED_IMAGE_FILTER_LINEAR} == vk.FormatFeatureFlags{}) {
        fmt.eprintln("texture image format does not support linear blitting!")
        os.exit(1)
    }

    commandBuffer, err := begin_command(r);
    defer end_command(r, &commandBuffer)

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