package engine 

import vk "vendor:vulkan"
import "core:fmt"
import "core:os"
import "core:mem"
import "core:math"
import "vendor:stb/image"
import "core:strings"

DepthImage :: struct{
    image: Image,
    view: vk.ImageView
}

Image :: struct {
    texture: vk.Image,
    memory: vk.DeviceMemory,
}

createImageViews :: proc(using ctx: ^Context) {
    using ctx.sc
    swapchain.attachments.views = make([]vk.ImageView, len(swapchain.images))

    for _, i in swapchain.images {
        swapchain.attachments.views[i] = createImageView(ctx, swapchain.images[i], swapchain.format, {.COLOR}, 1, "swapchain")
    }

}

createImageView :: proc(
    using ctx: ^Context, 
    image: vk.Image, 
    format: vk.Format, 
    aspectFlags: vk.ImageAspectFlags, 
    mips: u32,
    name: cstring,
) -> vk.ImageView {
    using ctx.vulkan

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

    nameInfo :vk.DebugUtilsObjectNameInfoEXT = {
        sType = vk.StructureType.DEBUG_UTILS_OBJECT_NAME_INFO_EXT,
        objectType = vk.ObjectType.IMAGE_VIEW,
        objectHandle = cast(u64)imageView,
        pObjectName = name
    }
    vk.SetDebugUtilsObjectNameEXT(device, &nameInfo)

    return imageView
}

createImage :: proc(using ctx: ^Context, w,h,mips : u32, numSamples: vk.SampleCountFlags, format: vk.Format, tiling: vk.ImageTiling, 
usage: vk.ImageUsageFlags, properties: vk.MemoryPropertyFlags, image: ^Image) {
    using ctx.vulkan
    
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
    using ctx.resource
    using ctx.vulkan
    vk.DestroyImageView(device, textures[0].view, nil)
    textures[0].view = createImageView(ctx, textures[0].handle.texture, .R8G8B8A8_SRGB, {.COLOR}, textures[0].mips, "texture")
}


createIdImageView :: proc(using ctx: ^Context) {    
    using ctx.id
    idImage.view = createImageView(ctx, idImage.image.texture, .R8G8B8A8_UNORM, {.COLOR}, 1, "id")
}

getBaseDirectory :: proc(gltfPath: string) -> string {
    lastSlash := strings.last_index(gltfPath, "/")
    if lastSlash == -1 {
        return "./"  // Current directory if no slashes
    }
    return gltfPath[:lastSlash+1]
}


createTextureImage :: proc(using ctx: ^Context, texture: ^Texture,
path: string, textureIndex: int){
    using ctx.vulkan
    using ctx.resource

    fmt.printf("Creating texture %d: %s\n", textureIndex, path)
    
    if !os.exists(path) {
        fmt.eprintf("Texture file does not exist: %s\n", path)
    }

    w, h, channels: i32 

    imageData := image.load(strings.clone_to_cstring(path), &w, &h, &channels, 4)
    defer image.image_free(imageData)

    if imageData == nil {
        fmt.eprintf("Failed to load texture: %s\n", path)
    }

    max :=  w > h ? h : w
    texture.mips = cast(u32)math.floor_f32(math.log2(cast(f32)max)) + 1
    fmt.println("Creating Vulkan image...")
    w32 := cast(u32)w
    h32 := cast(u32)h

    imageSize := cast(vk.DeviceSize)(w32 * h32 * 4)
    stagingBuffer : Buffer 
    createBuffer(ctx, imageSize, {.TRANSFER_SRC}, {.HOST_VISIBLE, .HOST_COHERENT}, &stagingBuffer,
    "imageStaging")

    data: rawptr
    vk.MapMemory(device, stagingBuffer.memory, 0, imageSize, {}, &data)
    mem.copy(data, imageData, cast(int)imageSize)
    vk.UnmapMemory(device, stagingBuffer.memory)
 
    createImage(ctx, w32, h32, texture.mips, {._1}, .R8G8B8A8_SRGB, .OPTIMAL, {.TRANSFER_SRC, .TRANSFER_DST, .SAMPLED}, {.DEVICE_LOCAL}, &texture.handle)
    transitionImageLayout(ctx, texture.handle.texture, .R8G8B8A8_SRGB, .UNDEFINED, .TRANSFER_DST_OPTIMAL, texture.mips)
    copyBufferToImage(ctx, stagingBuffer.buffer, w32, h32, texture)

    destroyBuffer("imageStaging", ctx.vulkan.device, stagingBuffer)
    generateMipmaps(ctx, .R8G8B8A8_SRGB, texture.handle.texture, w, h, texture)
}

createTextureSampler ::proc(using ctx:^Context, texture: ^Texture, path: string, textureIndex: int) -> vk.Sampler{
    using ctx.vulkan
    using ctx.resource

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
        maxLod = f32(texture.mips),
        mipLodBias = 0.0,
    }

    sampler: vk.Sampler
    if vk.CreateSampler(device, &samplerInfo, nil, &sampler) != .SUCCESS {

        fmt.eprintf("Failed to create sampler for texture: %s\n", path)
        vk.DestroyImageView(device, texture.view, nil)
        vk.DestroyImage(device, texture.handle.texture, nil)
        vk.FreeMemory(device, texture.handle.memory, nil)
        os.exit(1)
    }

    return sampler
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

createFontTextureImage :: proc(
    using ctx: ^Context, 
    texture: ^Texture,
    atlas_data: []u8,
    width, height: u32,
    name: string = "font_atlas",
) {
    using ctx.vulkan
    using ctx.resource

    fmt.printf("Creating font texture %s: %dx%d\n", name, width, height)

    imageSize := cast(vk.DeviceSize)(width * height)

    if len(atlas_data) != int(imageSize) {
        fmt.eprintf("ERROR: Font atlas data size mismatch. Expected %d, got %d\n", 
            imageSize, len(atlas_data))
        return
    }

    stagingBuffer: Buffer 
    createBuffer(ctx, imageSize, {.TRANSFER_SRC}, {.HOST_VISIBLE, .HOST_COHERENT}, &stagingBuffer, "fontStaging")
    defer destroyBuffer("fontStaging", device, stagingBuffer)

    data: rawptr
    vk.MapMemory(device, stagingBuffer.memory, 0, imageSize, {}, &data)
    mem.copy(data, raw_data(atlas_data), int(imageSize))
    vk.UnmapMemory(device, stagingBuffer.memory)

    createImage(ctx, width, height, 1, {._1}, .R8_UNORM, .OPTIMAL, 
                {.TRANSFER_DST, .SAMPLED}, {.DEVICE_LOCAL}, &texture.handle)
    
    transitionImageLayout(ctx, texture.handle.texture, .R8_UNORM, .UNDEFINED, .TRANSFER_DST_OPTIMAL, 1)
    copyBufferToImage(ctx, stagingBuffer.buffer, width, height, texture)
    transitionImageLayout(ctx, texture.handle.texture, .R8_UNORM, .TRANSFER_DST_OPTIMAL, .SHADER_READ_ONLY_OPTIMAL, 1)

    texture.view = createImageView(ctx, texture.handle.texture, .R8_UNORM, {.COLOR}, 1, strings.clone_to_cstring(name))
    
    texture.sampler = create_font_sampler(ctx)
    texture.mips = 1
    texture.uri = strings.clone_to_cstring(name)

    fmt.printf("SUCCESS: Created font texture %dx%d\n", width, height)
}