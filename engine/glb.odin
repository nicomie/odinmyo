package engine

import vk "vendor:vulkan"
import "core:fmt"
import "core:os"
import "core:mem"
import "core:c/libc"
import "vendor:stb/image"
import "vendor:cgltf"

import "core:math/linalg"
import "core:math"

import "core:strings"

Primitive :: struct {
    firstIndex: u32,
    indexCount: u32,
}

Mesh :: struct {
    primitives: []Primitive
}

Material :: struct {
    baseColorFactor: [4]f32,
    metallicFactor: f32,
    roughnessFactor: f32,
    baseColorTexture: ^cgltf.texture, 

    metallicRoughnessTexture: ^cgltf.texture,
    normalTexture: ^cgltf.texture, 
}

MeshObject :: struct {
    vertexBuffer: Buffer, 
    indexBuffer: Buffer,
    transform: linalg.Matrix4x4f32,
    material: ^cgltf.material,
}

loadTextures :: proc(using ctx: ^Context, data: ^cgltf.data) {
    using ctx.resource
    textures = make([]Texture, len(data.images))
    for i in 0..<len(data.images) {
        image := data.images[i]
        
        basePath := "glbs/box"
        texturePath := fmt.tprintf("%s%s", basePath, string(image.uri))
        
        // Create texture
        textures[i] = createTextureFromFile(ctx, texturePath, i)
    }
}

createTextureFromFile :: proc(using ctx: ^Context, path: string, textureIndex: int) -> Texture {
    using ctx.vulkan
    texture: Texture
    texture.uri = strings.clone_to_cstring(path)
    
    fmt.printf("Creating texture %d: %s\n", textureIndex, path)
    
    // Check if file exists first
    if !os.exists(path) {
        fmt.eprintf("Texture file does not exist: %s\n", path)
        return texture
    }
    
    // Load image data
    width, height: i32
    channels: i32
    imageData := image.load(strings.clone_to_cstring(path), &width, &height, &channels, 4)
    defer image.image_free(imageData)
    
    if imageData == nil {
        fmt.eprintf("Failed to load texture: %s\n", path)
        return texture
    }
    
    fmt.printf("Loaded texture: %dx%d, %d channels\n", width, height, channels)
    
    fmt.println("Creating Vulkan image...")
    imageCreateInfo := vk.ImageCreateInfo{
        sType = .IMAGE_CREATE_INFO,
        imageType = .D2,
        extent = {
            width = u32(width),
            height = u32(height),
            depth = 1,
        },
        mipLevels = 1,
        arrayLayers = 1,
        format = .R8G8B8A8_SRGB,
        tiling = .OPTIMAL,
        initialLayout = .UNDEFINED,
        usage = {.TRANSFER_DST, .SAMPLED},
        sharingMode = .EXCLUSIVE,
        samples = {._1},
    }
    
    if vk.CreateImage(device, &imageCreateInfo, nil, &texture.handle.texture) != .SUCCESS {
        fmt.eprintf("Failed to create image for texture: %s\n", path)
        return texture
    }
    
    fmt.println("Allocating image memory...")
    memRequirements: vk.MemoryRequirements
    vk.GetImageMemoryRequirements(device, texture.handle.texture, &memRequirements)
    
    allocInfo := vk.MemoryAllocateInfo{
        sType = .MEMORY_ALLOCATE_INFO,
        allocationSize = memRequirements.size,
        memoryTypeIndex = findMemType(
            physicalDevice,
            memRequirements.memoryTypeBits,
            {.DEVICE_LOCAL}
        ),
    }
    
    if vk.AllocateMemory(device, &allocInfo, nil, &texture.handle.memory) != .SUCCESS {
        fmt.eprintf("Failed to allocate image memory for texture: %s\n", path)
        vk.DestroyImage(device, texture.handle.texture, nil)
        return texture
    }
    fmt.println("Image memory allocated successfully")

    vk.BindImageMemory(device, texture.handle.texture, texture.handle.memory, 0)
    fmt.println("Image memory bound successfully")

    fmt.println("Creating staging buffer...")
    imageSize := vk.DeviceSize(width * height * 4)
    stagingBuffer: Buffer
    
    createBuffer(
        ctx,
        imageSize,
        {.TRANSFER_SRC},
        {.HOST_VISIBLE, .HOST_COHERENT},
        &stagingBuffer
    )

    
    fmt.println("Beginning command buffer for transfer...")
    cmdBuffer := beginCommand(ctx)
    
    // Transition to transfer destination
    barrier := vk.ImageMemoryBarrier{
        sType = .IMAGE_MEMORY_BARRIER,
        oldLayout = .UNDEFINED,
        newLayout = .TRANSFER_DST_OPTIMAL,
        srcQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
        dstQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
        image = texture.handle.texture,
        subresourceRange = {
            aspectMask = {.COLOR},
            baseMipLevel = 0,
            levelCount = 1,
            baseArrayLayer = 0,
            layerCount = 1,
        },
        srcAccessMask = {},
        dstAccessMask = {.TRANSFER_WRITE},
    }
    
    vk.CmdPipelineBarrier(
        cmdBuffer,
        {.TOP_OF_PIPE}, {.TRANSFER},
        {}, 0, nil, 0, nil, 1, &barrier
    )
    
    // Copy buffer to image
    region := vk.BufferImageCopy{
        bufferOffset = 0,
        bufferRowLength = 0,
        bufferImageHeight = 0,
        imageSubresource = {
            aspectMask = {.COLOR},
            mipLevel = 0,
            baseArrayLayer = 0,
            layerCount = 1,
        },
        imageOffset = {0, 0, 0},
        imageExtent = {u32(width), u32(height), 1},
    }
    
    vk.CmdCopyBufferToImage(
        cmdBuffer,
        stagingBuffer.buffer,
        texture.handle.texture,
        .TRANSFER_DST_OPTIMAL,
        1, &region
    )
    
    // Transition to shader read layout
    barrier.oldLayout = .TRANSFER_DST_OPTIMAL
    barrier.newLayout = .SHADER_READ_ONLY_OPTIMAL
    barrier.srcAccessMask = {.TRANSFER_WRITE}
    barrier.dstAccessMask = {.SHADER_READ}
    
    vk.CmdPipelineBarrier(
        cmdBuffer,
        {.TRANSFER}, {.FRAGMENT_SHADER},
        {}, 0, nil, 0, nil, 1, &barrier
    )
    
    endCommand(ctx, &cmdBuffer)
    
    // Create image view
    viewInfo := vk.ImageViewCreateInfo{
        sType = .IMAGE_VIEW_CREATE_INFO,
        image = texture.handle.texture,
        viewType = .D2,
        format = .R8G8B8A8_SRGB,
        components = {
            r = .IDENTITY,
            g = .IDENTITY,
            b = .IDENTITY,
            a = .IDENTITY,
        },
        subresourceRange = {
            aspectMask = {.COLOR},
            baseMipLevel = 0,
            levelCount = 1,
            baseArrayLayer = 0,
            layerCount = 1,
        },
    }
    
    if vk.CreateImageView(device, &viewInfo, nil, &texture.view) != .SUCCESS {
        fmt.eprintf("Failed to create image view for texture: %s\n", path)
        vk.DestroyImage(device, texture.handle.texture, nil)
        vk.FreeMemory(device, texture.handle.memory, nil)
        return texture
    }
    
    // Create sampler
    samplerInfo := vk.SamplerCreateInfo{
        sType = .SAMPLER_CREATE_INFO,
        magFilter = .LINEAR,
        minFilter = .LINEAR,
        addressModeU = .REPEAT,
        addressModeV = .REPEAT,
        addressModeW = .REPEAT,
        anisotropyEnable = true,
        maxAnisotropy = 16.0,
        borderColor = .INT_OPAQUE_BLACK,
        unnormalizedCoordinates = false,
        compareEnable = false,
        compareOp = .ALWAYS,
        mipmapMode = .LINEAR,
        mipLodBias = 0.0,
        minLod = 0.0,
        maxLod = 0.0,
    }
    
    if vk.CreateSampler(device, &samplerInfo, nil, &texture.sampler) != .SUCCESS {
        fmt.eprintf("Failed to create sampler for texture: %s\n", path)
        vk.DestroyImageView(device, texture.view, nil)
        vk.DestroyImage(device, texture.handle.texture, nil)
        vk.FreeMemory(device, texture.handle.memory, nil)
        return texture
    }
    
    texture.mips = 1
    fmt.printf("Successfully created texture %d: %s\n", textureIndex, path)
    
    return texture
}

loadAllTextures :: proc(using ctx: ^Context, data: ^cgltf.data) {
    using ctx.resource
    
    fmt.printf("Loading %d textures...\n", len(data.images))
    
    // Create array for all textures
    textures = make([]Texture, len(data.images))
    
    for i in 0..<len(data.images) {
        image := data.images[i]
        
        if image.uri == nil {
            fmt.eprintf("Texture %d has no URI (embedded textures not supported)\n", i)
            continue
        }
        
        // Build proper path - adjust base path as needed
        basePath := "glbs/SciFiHelmet/glTF/"
        texturePath := fmt.tprintf("%s%s", basePath, string(image.uri))
        fmt.printf("Loading texture %d: %s\n", i, texturePath)
        
        // Create texture with correct index
        fmt.println("File exists, proceeding with texture creation...")
        textures[i] = createTextureFromFile(ctx, texturePath, i)
    }
}

processMaterials :: proc(data: ^cgltf.data) -> []Material {
    materials := make([]Material, len(data.materials))
    
    for i in 0..<len(data.materials) {
        gltfMaterial := data.materials[i]
        material : Material
        
        if gltfMaterial.pbr_metallic_roughness != {} {
            pbr := gltfMaterial.pbr_metallic_roughness
            material.baseColorFactor = pbr.base_color_factor
            material.metallicFactor = pbr.metallic_factor
            material.roughnessFactor = pbr.roughness_factor
            
            if pbr.base_color_texture != {} && pbr.base_color_texture.texture != {} {
                material.baseColorTexture = pbr.base_color_texture.texture
            }
            
            if pbr.metallic_roughness_texture != {} && pbr.metallic_roughness_texture.texture != {} {
                material.metallicRoughnessTexture = pbr.metallic_roughness_texture.texture 
            }
        }
        
        if gltfMaterial.normal_texture != {} && gltfMaterial.normal_texture.texture != {} {
            material.normalTexture = gltfMaterial.normal_texture.texture
        }
        
        materials[i] = material
    }
    
    return materials
}

setupGlb :: proc(using ctx: ^Context, filePath: cstring) {
    using ctx.resource
    
    data, res := cgltf.parse_file({}, filePath)
    if res != .success {
        fmt.eprintf("Failed to parse GLTF: %s\n", filePath)
        return
    }
    defer cgltf.free(data)
    
    if cgltf.load_buffers({}, data, filePath) != .success {
        fmt.eprintf("Failed to load buffers: %s\n", filePath)
        return
    }
    
    loadAllTextures(ctx, data)
    
    materials := processMaterials(data)
    
    for meshIndex in 0..<len(data.meshes) {
        mesh := data.meshes[meshIndex]
        
        for primitiveIndex in 0..<len(mesh.primitives) {
            primitive := mesh.primitives[primitiveIndex]
            
            // Process vertices and indices
            vertices, indices := processPrimitive(primitive)
            
            if len(vertices) == 0 || len(indices) == 0 {
                fmt.eprintf("Skipping primitive with no vertices/indices\n")
                continue
            }
            
            // Create buffers
            vBuffer := createVertexBuffer(ctx, vertices)
            iBuffer := createIndexBuffer(ctx, indices)
            
            // Store with material pointer
            append(&meshes, MeshObject{
                vertexBuffer = vBuffer,
                indexBuffer = iBuffer,
                transform = linalg.MATRIX4F32_IDENTITY,
                material = primitive.material,  // Store the pointer directly
            })
            
            fmt.printf("Loaded primitive with %d vertices, %d indices\n", 
                    len(vertices), len(indices))
        }
    }
}

processPrimitive :: proc(primitive: cgltf.primitive) -> ([]Vertex, []u32) {
    vertices: [dynamic]Vertex
    indices: [dynamic]u32

    // Process vertex attributes
    for attrIndex in 0..<len(primitive.attributes) {
        attribute := primitive.attributes[attrIndex]
        accessor := attribute.data
        
        #partial switch attribute.type {
            case .position:
                // Ensure we have the right number of vertices
                if len(vertices) == 0 {
                    vertices = make([dynamic]Vertex, accessor.count)
                }
                
                for j in 0..<accessor.count {
                    position: [3]f32
                    res:=cgltf.accessor_read_float(accessor, j, &position[0], 3)
                    vertices[j].pos = position
                    vertices[j].color = {1.0, 1.0, 1.0} // Default white
                }

            case .texcoord:
                for j in 0..<accessor.count {
                    if j >= len(vertices) {
                        // Create vertex if it doesn't exist yet
                        append(&vertices, Vertex{color = {1.0, 1.0, 1.0}})
                    }
                    texcoord: [2]f32
                    res:=cgltf.accessor_read_float(accessor, j, &texcoord[0], 2)
                    vertices[j].texCoord = texcoord
                }

            case .normal:
                // Optional: store normals if you need them for lighting
                for j in 0..<accessor.count {
                    if j >= len(vertices) {
                        append(&vertices, Vertex{color = {1.0, 1.0, 1.0}})
                    }
                    // You could add normals to your Vertex struct if needed
                    // normal: [3]f32
                    // cgltf.accessor_read_float(accessor, j, &normal[0], 3)
                    // vertices[j].normal = normal
                }

            case .color:
                for j in 0..<accessor.count {
                    if j >= len(vertices) {
                        append(&vertices, Vertex{})
                    }
                    color: [4]f32
                    res:=cgltf.accessor_read_float(accessor, j, &color[0], 4)
                    vertices[j].color = {color[0], color[1], color[2]} // RGB only
                }
        }
    }

    // Process indices
    if primitive.indices != nil {
        index_accessor := primitive.indices
        
        for i in 0..<index_accessor.count {
            idx := cgltf.accessor_read_index(index_accessor, i)
            append(&indices, u32(idx))
        }
    } else {
        // No indices provided, generate them sequentially
        for i in 0..<len(vertices) {
            append(&indices, u32(i))
        }
    }

    return vertices[:], indices[:]
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