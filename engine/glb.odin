package engine

import vk "vendor:vulkan"
import "core:fmt"

import "vendor:stb/image"
import "vendor:cgltf"

import "core:math/linalg"


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
    vertexBuffer: ^Buffer, 
    indexBuffer: ^Buffer,
    transform: Mat4,
    material: ^cgltf.material,
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

createTextureFromFile :: proc(using ctx: ^Context, path: string, textureIndex: int) -> ^Texture {
    using ctx.vulkan
    texture := new(Texture)
    createTextureImage(ctx, texture, path, textureIndex)
    texture.view = createImageView(ctx, texture.handle.texture, .R8G8B8A8_SRGB, {.COLOR}, texture.mips, "texture")
    texture.sampler = createTextureSampler(ctx, texture, path, textureIndex)
      fmt.println("here")

    return texture
}

loadAllTextures :: proc(using ctx: ^Context, data: ^cgltf.data) {
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
                material = primitive.material,  
            })

            append(&meshes, MeshObject{
               vertexBuffer = vBuffer,
               indexBuffer = iBuffer,
               transform = linalg.matrix4_translate_f32(linalg.Vector3f32{2, 2, 2}),
               material = primitive.material,  
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