package engine

import "core:c/libc/tests"
import vk "vendor:vulkan"
import "core:fmt"
import "core:os"
import "vendor:stb/image"
import "vendor:cgltf"
import "core:strings"
import "core:mem"
import "core:math"
import "core:math/linalg"

ResourceManager :: struct {
    meshes: [dynamic]Mesh,
    materials: []Material,
    materialLookup: map[^cgltf.material]int,
    textures: []^Texture,
    meshObjects: [dynamic]MeshObject,
}

Material :: struct {
    name: string,

    baseColorFactor: [4]f32,
    metallicFactor: f32,
    roughnessFactor: f32,

    baseColorTexIndex: ^cgltf.texture,
    metallicRoughnessTexIndex: ^cgltf.texture,
    normalTexIndex: ^cgltf.texture,

    alphaMode: cgltf.alpha_mode,
    alphaCutoff: f32,
    doubleSided: b32,

    descriptorSets: [MAX_FRAMES_IN_FLIGHT]vk.DescriptorSet,
    materialUBO: []Buffer,
}

MaterialUBO :: struct {
    color: Vec4,
    params : Vec4
}

Texture :: struct {
    handle: Image,
    view: vk.ImageView,
    sampler: vk.Sampler,
    mips: u32,
    uri: cstring,
}

Primitive :: struct {
    firstIndex: i32,
    indexCount: i32,
    firstVertex: i32,
    vertexCount: i32,
    materialIndex: int,
}

Mesh :: struct {
    name: string,
    vertexBuffer: ^Buffer,
    indexBuffer: ^Buffer,
    primitives: []Primitive,
}

MeshObject :: struct {
    meshIndex: int,
    worldTransform: Mat4,
}

cgltf_material_index :: proc(data: ^cgltf.data, m: ^cgltf.material) -> int {
    for i in 0..<len(data.materials) {
        if &data.materials[i] == m {
                     fmt.printf("hit for %v against %v \n", m.name, data.materials[i].name)

            return i
        } else  {
            fmt.printf("no hit for %v against %v \n", m.name, data.materials[i])

        }
    }
    return -1
}

cgltf_image_index :: proc(data: ^cgltf.data, m: ^cgltf.image) -> int {
    for i in 0..<len(data.images) {
        if &data.images[i] == m {
            return i
        }
    }
    return -1
}

cgltf_buffer_index :: proc(data: ^cgltf.data, m: ^cgltf.buffer) -> int {
    for i in 0..<len(data.buffers) {
        if &data.buffers[i] == m {
            return i
        }
    }
    return -1
}

loadTextureFromImage :: proc(ctx: ^Context, img: ^cgltf.image, data: ^cgltf.data) -> ^Texture {
    if img == nil do return nil
    
    bytes, size := loadCgltfImageBytes(img, data)
    if bytes == nil || size == 0 {
        return nil
    }

    tex := createTextureFromMemory(ctx, bytes, size, img.uri)
    return tex
}


processSingleMaterial :: proc(gm: ^cgltf.material, index: int) -> Material {
    m := Material{}
    
    m.baseColorFactor = {1.0, 1.0, 1.0, 1.0}
    m.metallicFactor = 1.0
    m.roughnessFactor = 1.0
    
    // Get name from the actual material pointer
    if gm.name != nil {
        m.name = strings.clone(string(gm.name))
    } else {
        m.name = fmt.tprintf("material_%d", index)
    }

    if gm.has_pbr_metallic_roughness {
        pbr := gm.pbr_metallic_roughness
        m.baseColorFactor = pbr.base_color_factor
        m.metallicFactor = pbr.metallic_factor 
        m.roughnessFactor = pbr.roughness_factor

        if pbr.base_color_texture != {} && pbr.base_color_texture.texture != {} {
            m.baseColorTexIndex = pbr.base_color_texture.texture

            m.alphaMode = gm.alpha_mode
            m.alphaCutoff = gm.alpha_cutoff
            m.doubleSided = gm.double_sided
        }
        
        if pbr.metallic_roughness_texture != {} && pbr.metallic_roughness_texture.texture != {} {
            m.metallicRoughnessTexIndex = pbr.metallic_roughness_texture.texture
        }

      
    }

    if gm.normal_texture != {} && gm.normal_texture.texture != {} {
        m.normalTexIndex = gm.normal_texture.texture
    }

    return m
}

processNode :: proc(using ctx: ^Context, node: ^cgltf.node, parent_transform: Mat4, rm: ^ResourceManager) {
    local_transform := getNodeTransform(node)
    world_transform := parent_transform * local_transform
    
    if node.mesh != nil {
        processMeshNode(ctx, node, node.mesh, world_transform, rm)
    }
    
    if node.children != nil {
        for i in 0..<len(node.children) {
            processNode(ctx, node.children[i], world_transform, rm)
        }
    }
}

processMeshNode :: proc(using ctx: ^Context, node: ^cgltf.node, mesh: ^cgltf.mesh, world_transform: Mat4, rm: ^ResourceManager) {
    fmt.printf("Processing mesh node: %s\n", node.name != nil ? string(node.name) : "unnamed")
    
    verts: [dynamic]Vertex 
    indices: [dynamic]u32
    primitives: [dynamic]Primitive

    baseVertex :i32 = 0
    baseIndex :i32 = 0

    for p in mesh.primitives {
        v, i := processPrimitive(p)
      
        firstV := baseVertex
        append_elems(&verts, ..v[:])
        vertexCount := cast(i32)len(v)
        baseVertex += vertexCount

        firstI := baseIndex
        for j in 0..<len(i) {
            append(&indices, cast(u32)i[j] + cast(u32)firstV)
        }
        indexCount := cast(i32)len(i)
        baseIndex += indexCount 

        matIdx := -1
        if p.material != nil {
            if idx, ok := rm.materialLookup[p.material]; ok {
                matIdx = idx
            }
        }

        append(&primitives, Primitive{
            firstVertex = firstV,
            vertexCount = cast(i32)len(v),
            firstIndex = firstI,
            indexCount = cast(i32)len(i),
            materialIndex = matIdx
        })
    }

    if len(verts) == 0 || len(indices) == 0 {
        return
    }

    vb := createVertexBuffer(ctx, verts[:])
    ib := createIndexBuffer(ctx, indices[:])

    mesh_index := len(rm.meshes)
    append(&rm.meshes, Mesh{
        name = strings.clone_from_cstring(mesh.name),
        vertexBuffer = vb,
        indexBuffer = ib,
        primitives = primitives[:]
    })

    append(&rm.meshObjects, MeshObject{
        mesh_index, 
        world_transform
    })
    
    fmt.printf("Created MeshObject %d with transform for node '%s'\n", 
        mesh_index, node.name != nil ? string(node.name) : "unnamed")
} 

collectMaterialsFromNode :: proc(node: ^cgltf.node, unique_materials: ^map[^cgltf.material]bool) {
    if node.mesh != nil && node.mesh.primitives != nil {
        for prim in node.mesh.primitives {
            if prim.material != nil {
                unique_materials[prim.material] = true
            }
        }
    }
    
    if node.children != nil {
        for i in 0..<len(node.children) {
            collectMaterialsFromNode(node.children[i], unique_materials)
        }
    }
}


setupGlb :: proc(using ctx: ^Context, path: cstring) {
    rm := &ctx.resource
    
    data, res := cgltf.parse_file({}, path)
    if res != .success {
        fmt.eprintf("Failed to parse GLTF: %s\n", path)
        return
    }
    defer cgltf.free(data)
    
    if cgltf.load_buffers({}, data, path) != .success {
        fmt.eprintf("Failed to load buffers: %s\n", path)
        return
    }

    baseDir := getBaseDirectory(string(path))
    fmt.printf("Base directory for textures: %s\n", baseDir)

    loadAllTextures(ctx, data, baseDir)
    
    processAllMaterials(rm, data)

    if data.scene != nil && data.scene.nodes != nil {
        for i in 0..<len(data.scene.nodes) {
            processNode(ctx, data.scene.nodes[i], linalg.MATRIX4F32_IDENTITY, rm)
        }   
    } else {
        fmt.println("No scene found")
    }
}

getNodeTransform :: proc(node: ^cgltf.node) -> Mat4 {
    transform := linalg.MATRIX4F32_IDENTITY
    
    if node.has_translation {
        translation := linalg.matrix4_translate(node.translation)
        transform = translation
    }
    
    if node.has_rotation {
        rotation := quaternion(
            real = node.rotation.w,
            imag = node.rotation.x,
            jmag = node.rotation.y,
            kmag = node.rotation.z

        )
        rotationMat := linalg.to_matrix4f32(rotation)
        transform = transform * rotationMat 
    }
    
    if node.has_scale {
        scale := linalg.matrix4_scale(node.scale)
        transform = transform * scale
    }
    
    if node.has_matrix {
        a: Mat4
        for i in 0..<16 {
            a[i/4][i%4] = node.matrix_[i]
        }
        transform = a
    }
    
    if node.parent == nil do transform = transform * linalg.matrix4_translate_f32(Vec3{0, 0, 1})
    return transform
}

processAllMaterials :: proc(rm: ^ResourceManager, data: ^cgltf.data) {
    unique_materials: map[^cgltf.material]bool
    defer delete(unique_materials)
    
    // Collect all materials used in the entire scene
    if data.scene != nil && data.scene.nodes != nil {
        for i in 0..<len(data.scene.nodes) {
            collectMaterialsFromNode(data.scene.nodes[i], &unique_materials)
        }
    }
    
    // Process the collected materials
    rm.materials = make([]Material, len(unique_materials))
    rm.materialLookup = make(map[^cgltf.material]int)
    
    j := 0
    for material, _ in unique_materials {
        m := processSingleMaterial(material, j)
        rm.materials[j] = m
        rm.materialLookup[material] = j
        j += 1
    }
}

loadAllTextures :: proc(using ctx: ^Context, data: ^cgltf.data, path: string) {
    using ctx.resource
    
    fmt.printf("Loading %d textures...\n", len(data.images))
    
    // Create array for all textures
    textures = make([]^Texture, len(data.images))
    
    for i in 0..<len(data.images) {
        image := data.images[i]
        
        if image.uri == nil {
            fmt.eprintf("Texture %d has no URI (embedded textures not supported)\n", i)
            continue
        }
        
        // Build proper path - adjust base path as needed
        basePath := path
        texturePath := fmt.tprintf("%s%s", basePath, string(image.uri))
        fmt.printf("Loading texture %d: %s\n", i, texturePath)
        
        // Create texture with correct index
        fmt.println("File exists, proceeding with texture creation...")
        textures[i] = createTextureFromFile(ctx, texturePath, i)
    }
}

createTextureFromFile :: proc(using ctx: ^Context, path: string, textureIndex: int) -> ^Texture {
    using ctx.vulkan
    texture := new(Texture)
    createTextureImage(ctx, texture, path, textureIndex)
    texture.view = createImageView(ctx, texture.handle.texture, .R8G8B8A8_SRGB, {.COLOR}, texture.mips, "texture")
    texture.sampler = createTextureSampler(ctx, texture, path, textureIndex)
      fmt.println("here")

    return texture
}

processMaterials :: proc(rm: ^ResourceManager, data: ^cgltf.data, ctx: ^Context) -> []Material {
    if data == nil || data.materials == nil do return make([]Material, 0)
    materials := make([]Material, len(data.materials))

    for i in 0..<len(data.materials) {
        gm := &data.materials[i]
        m := Material{}
        
        m.baseColorFactor = {1.0, 1.0, 1.0, 1.0}
        m.metallicFactor = 1.0
        m.roughnessFactor = 1.0
        
        m.name = strings.clone_from_cstring(gm.name) if gm.name != nil else fmt.tprintf("material_%d", i)
        fmt.printf("Material: %s\n", m.name)

        if gm.has_pbr_metallic_roughness {
            pbr := gm.pbr_metallic_roughness
            m.baseColorFactor = pbr.base_color_factor
            m.metallicFactor = pbr.metallic_factor 
            m.roughnessFactor = pbr.roughness_factor

            if pbr.base_color_texture != {} && pbr.base_color_texture.texture != {} {
                m.baseColorTexIndex = pbr.base_color_texture.texture
            }
            
            if pbr.metallic_roughness_texture != {} && pbr.metallic_roughness_texture.texture != {} {
                m.metallicRoughnessTexIndex = pbr.metallic_roughness_texture.texture
            }
        }

        if gm.normal_texture != {} && gm.normal_texture.texture != {} {
            m.normalTexIndex = gm.normal_texture.texture
        }

        materials[i] = m
    }

    return materials
}

findTextureIndex :: proc(data: ^cgltf.data, texture: ^cgltf.texture) -> int {
    if data.textures == nil || texture == nil do return -1
    
    for i in 0..<len(data.textures) {
        if &data.textures[i] == texture {
            fmt.println(&data.textures[i] == texture )
            return i
        }
    }
    return -1
}

processPrimitive :: proc(p: cgltf.primitive) -> ([]Vertex, []u32) {
    vertices: [dynamic]Vertex
    indices: [dynamic]u32

    for attr in p.attributes {
        accessor := attr.data
        
        #partial switch attr.type {
            case .position:
                if len(vertices) == 0 {
                    vertices = make([dynamic]Vertex, accessor.count)
                }
                
                for i in 0..<accessor.count {
                    position: [3]f32
                    res:=cgltf.accessor_read_float(accessor, i, &position[0], 3)
                    vertices[i].pos = position
                    vertices[i].color = {1.0, 1.0, 1.0}
                }

            case .texcoord:
                for i in 0..<accessor.count {
                    if i >= len(vertices) {
                        append(&vertices, Vertex{color = {1.0, 1.0, 1.0}})
                    }
                    texcoord: [2]f32
                    res:=cgltf.accessor_read_float(accessor, i, &texcoord[0], 2)
                    vertices[i].texCoord = texcoord
                }

            case .normal:
                for j in 0..<accessor.count {
                    if j >= len(vertices) {
                        append(&vertices, Vertex{color = {1.0, 1.0, 1.0}})
                    }
                    normal: [3]f32
                    cgltf.accessor_read_float(accessor, j, &normal[0], 3)
                    vertices[j].normal = normal
                }

            case .color:
                for i in 0..<accessor.count {
                    if i >= len(vertices) {
                        append(&vertices, Vertex{})
                    }
                    color: [4]f32
                    res:=cgltf.accessor_read_float(accessor, i, &color[0], 4)
                    vertices[i].color = {color[0], color[1], color[2]} // RGB only
                }
        }
    }

    if p.indices != nil {   
        index_accessor := p.indices
        for i in 0..<p.indices.count {
            idx := cgltf.accessor_read_index(index_accessor, i)
            append(&indices, u32(idx))
        }
    } else {
        for i in 0..<len(vertices) {
            append(&indices, u32(i))
        }
    }

    return vertices[:], indices[:]
}


createTextureImageFromPixels :: proc(using ctx: ^Context, texture: ^Texture, pixels: rawptr, w, h: i32, textureIndex: int) {
    using ctx.vulkan

    w32 := cast(u32)w
    h32 := cast(u32)h
    channels :u32 = 4
    imageSize := cast(vk.DeviceSize)(w32 * h32 * channels)

    staging: Buffer
    createBuffer(ctx, imageSize, {.TRANSFER_SRC}, {.HOST_VISIBLE, .HOST_COHERENT}, &staging, "imageStaging")
    data: rawptr
    vk.MapMemory(device, staging.memory, 0, imageSize, {}, &data)
    mem.copy(data, pixels, cast(int)imageSize)
    vk.UnmapMemory(device, staging.memory)

    texture.mips = cast(u32)math.floor_f32(math.log2(cast(f32)math.min(w, h))) + 1

    createImage(ctx, w32, h32, texture.mips, {._1}, .R8G8B8A8_SRGB, .OPTIMAL,
        {.TRANSFER_SRC, .TRANSFER_DST, .SAMPLED}, {.DEVICE_LOCAL}, &texture.handle)

    transitionImageLayout(ctx, texture.handle.texture, .R8G8B8A8_SRGB, .UNDEFINED, .TRANSFER_DST_OPTIMAL, texture.mips)
    copyBufferToImage(ctx, staging.buffer, w32, h32, texture)

    destroyBuffer("imageStaging", ctx.vulkan.device, staging)
    generateMipmaps(ctx, .R8G8B8A8_SRGB, texture.handle.texture, w, h, texture)
}

createTextureFromMemory :: proc(using ctx: ^Context, bytes: []u8, size: int, uri: cstring) -> ^Texture {
    using ctx.vulkan

    w, h, channels: i32
    pixels := image.load_from_memory(raw_data(bytes), cast(i32)size, &w, &h, &channels, 4)
    if pixels == nil {
        fmt.eprintf("stb failed to decode image in memory\n")
        return nil
    }
    defer image.image_free(pixels)

    tex := new(Texture)
    createTextureImageFromPixels(ctx, tex, pixels, w, h, len(ctx.resource.textures))
    tex.view = createImageView(ctx, tex.handle.texture, .R8G8B8A8_SRGB, {.COLOR}, tex.mips, "texture")
    tex.sampler = createTextureSampler(ctx, tex, "memory", len(ctx.resource.textures))
    tex.uri = "";

    return tex
}

loadCgltfImageBytes :: proc(img: ^cgltf.image, data: ^cgltf.data) -> ([]u8, int) {
    if img == nil do return nil, 0

    if img.uri != nil {
        path := fmt.tprintf("glbs/SciFiHelmet/glTF/%s", string(img.uri))
        file , ok := os.read_entire_file(path)
        if !ok {
            fmt.eprintf("Failed to read image file: %s\n", path)
            return nil, 0
        }
        return file, len(file)
    }

    if img.buffer_view != nil {
        bv := img.buffer_view
        buf := data.buffers[cgltf_buffer_index(data, bv.buffer)]

        start := cast(int)(bv.offset)
        size  := cast(int)(bv.size)

        base := buf.data
        return ([^]u8)(base)[start : start + size], size
    }

    fmt.eprintln("Unsupported cgltf.image type (no uri, no buffer_view)")
    return nil, 0
}


// CHECK 
/*
createTextureFromFile :: proc(using ctx: ^Context, path: string, textureIndex: int) -> ^Texture {
    using ctx.vulkan
    texture := new(Texture)
    createTextureImage(ctx, texture, path, textureIndex)
    texture.view = createImageView(ctx, texture.handle.texture, .R8G8B8A8_SRGB, {.COLOR}, texture.mips, "texture")
    texture.sampler = createTextureSampler(ctx, texture, path, textureIndex)
      fmt.println("here")

    return texture
}

loadTextures :: proc(using ctx: ^Context, data: ^cgltf.data) {
    using ctx.resource
    textures = make([]^Texture, len(data.images))
    for i in 0..<len(data.images) {
        image := data.images[i]
        
        basePath := "glbs/box"
        texturePath := fmt.tprintf("%s%s", basePath, string(image.uri))
        
        // Create texture
        textures[i] = createTextureFromFile(ctx, texturePath, i)
    }
}
*/