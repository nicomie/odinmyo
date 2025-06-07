package app

import vk "vendor:vulkan"
import "core:mem"
import "core:fmt"
import "core:os"
import "core:math"
import "vendor:stb/image"

import "core:c/libc"
import "core:strings"


Texture :: struct {
    image: Image,
    memory: vk.DeviceMemory,
    view: vk.ImageView,
    sampler: vk.Sampler,
    mip_levels: u32,
    extent: vk.Extent2D,
}

create_texture :: proc(
    r: ^Renderer,
    file_path: string,
) -> (texture: Texture, err: vk.Result) {
    
    // Load image file
    f := libc.fopen(strings.clone_to_cstring(file_path), "rb")
    if f == nil {
        fmt.eprintf("Failed to open texture file: %s\n", file_path)
        return {}, .ERROR_UNKNOWN
    }
    defer libc.fclose(f)

    width, height, channels: i32
    loaded_image := image.load_from_file(f, &width, &height, &channels, 4)
    defer image.image_free(loaded_image)
    
    if loaded_image == nil {
        fmt.eprintln("Failed to load texture image")
        return {}, .ERROR_UNKNOWN
    }

    // Calculate mip levels
    max_dim := max(width, height)
    mip_levels := cast(u32)math.floor_f32(math.log2(cast(f32)max_dim)) + 1
    texture.mip_levels = mip_levels
    texture.extent = {cast(u32)width, cast(u32)height}

    // Create staging buffer
    image_size := vk.DeviceSize(width * height * 4)
    staging_buffer: Buffer
    defer destroy_buffer(r, staging_buffer)

    create_buffer(r, image_size, {.TRANSFER_SRC}, {.HOST_VISIBLE, .HOST_COHERENT}, &staging_buffer, loaded_image)

    // Create texture image
    create_image(r, 
        cast(u32)width, 
        cast(u32)height, 
        mip_levels, 
        {._1}, 
        .R8G8B8A8_SRGB, 
        .OPTIMAL, 
        {.TRANSFER_SRC, .TRANSFER_DST, .SAMPLED}, 
        {.DEVICE_LOCAL}, 
        &texture.image, 
    )

    // Transition and copy
    transition_image_layout(r, texture.image.texture, .R8G8B8A8_SRGB, .UNDEFINED, .TRANSFER_DST_OPTIMAL, mip_levels)
    copy_buffer_to_image(r, &texture.image, staging_buffer.buffer, cast(u32)width, cast(u32)height)
    generate_mipmaps(r, .R8G8B8A8_SRGB, texture.image.texture, width, height)

    // Create image view
    texture.view = create_image_view(r, texture.image.texture, .R8G8B8A8_SRGB, {.COLOR}, mip_levels)

    // Create sampler
    texture.sampler = create_texture_sampler(r, mip_levels)

    return texture, .SUCCESS
}

create_texture_image :: proc(using r: ^Renderer) {
    // todo dynamic texture
    f := libc.fopen(r.meshes[0].uri, "rb")
    if f == nil {
        fmt.eprintf("failed to fopen file \n", r.meshes[0].uri)
        os.exit(1)
    }
    defer libc.fclose(f)

    w, h, channels: i32 
    
    loadedImage := image.load_from_file(f, &w, &h, &channels, 4); defer image.image_free(loadedImage)

    max :=  w > h ? h : w
    mipLevels := cast(u32)math.floor_f32(math.log2(cast(f32)max)) + 1

    if loadedImage == nil {
        fmt.eprintln("failed to load image via load_from_file")
        os.exit(1)
    }
    w32 := cast(u32)w
    h32 := cast(u32)h

    imageSize := cast(vk.DeviceSize)(w32 * h32 * 4)
    stagingBuffer : Buffer 
    create_buffer(r, imageSize, {.TRANSFER_SRC}, {.HOST_VISIBLE, .HOST_COHERENT}, &stagingBuffer)

    data: rawptr
    vk.MapMemory(device, stagingBuffer.memory, 0, imageSize, {}, &data)
    mem.copy(data, loadedImage, cast(int)imageSize)
    vk.UnmapMemory(device, stagingBuffer.memory)
 
    create_image(r, w32, h32, mipLevels, {._1}, .R8G8B8A8_SRGB, .OPTIMAL, {.TRANSFER_SRC, .TRANSFER_DST, .SAMPLED}, {.DEVICE_LOCAL}, &texture.image)
    transition_image_layout(r, texture.image.texture, .R8G8B8A8_SRGB, .UNDEFINED, .TRANSFER_DST_OPTIMAL, mipLevels)
    copy_buffer_to_image(r, &texture.image, stagingBuffer.buffer, w32, h32)

    vk.DestroyBuffer(device, stagingBuffer.buffer, nil)
    vk.FreeMemory(device, stagingBuffer.memory, nil)

    generate_mipmaps(r, .R8G8B8A8_SRGB, texture.image.texture, w, h)

}

create_texture_image_view :: proc(using r: ^Renderer) {    
    texture.view = create_image_view(r, texture.image.texture, .R8G8B8A8_SRGB, {.COLOR}, 1)
}

destroy_texture :: proc(r: ^Renderer, texture: ^Texture) {
    vk.DestroySampler(r.device, texture.sampler, nil)
    vk.DestroyImageView(r.device, texture.view, nil)
    vk.DestroyImage(r.device, texture.image.texture, nil)
    vk.FreeMemory(r.device, texture.image.memory, nil)
}

create_texture_sampler :: proc(r: ^Renderer, mip_levels: u32) -> vk.Sampler {
    props: vk.PhysicalDeviceProperties
    vk.GetPhysicalDeviceProperties(r.physicalDevice, &props)

    sampler_info := vk.SamplerCreateInfo{
        sType = .SAMPLER_CREATE_INFO,
        magFilter = .LINEAR,
        minFilter = .LINEAR,
        mipmapMode = .LINEAR,
        addressModeU = .REPEAT,
        addressModeV = .REPEAT,
        addressModeW = .REPEAT,
        mipLodBias = 0.0,
        anisotropyEnable = true,
        maxAnisotropy = props.limits.maxSamplerAnisotropy,
        compareEnable = false,
        compareOp = .ALWAYS,
        minLod = 0.0,
        maxLod = cast(f32)mip_levels,
        borderColor = .INT_OPAQUE_BLACK,
        unnormalizedCoordinates = false,
    }

    sampler: vk.Sampler
    if vk.CreateSampler(r.device, &sampler_info, nil, &sampler) != .SUCCESS {
        fmt.eprintf("failed to create sampler")
        os.exit(1)
    }
    return sampler
}