package engine

import vk "vendor:vulkan"
import "core:fmt"
import "core:os"

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
    baseColorTextureIndex: u32
}

MeshObject :: struct {
    vertexBuffer: Buffer, 
    indexBuffer: Buffer,
    transform: linalg.Matrix4x4f32,
}

loadTextures :: proc(using ctx: ^Context, data: ^cgltf.data) {
    s := [?]string{"textures/", string(data.images[0].uri)}
    uri = strings.clone_to_cstring(strings.concatenate(s[:]))
}

setupGlb :: proc(using ctx: ^Context) {
    v, i := loadGlbModel(ctx)
    vBuffer: Buffer
    iBuffer: Buffer

    vBuffer = createVertexBuffer(ctx, v)
    iBuffer = createIndexBuffer(ctx, i)

    append(&meshes, MeshObject{
        vertexBuffer = vBuffer,
        indexBuffer = iBuffer,
        transform = linalg.MATRIX4F32_IDENTITY,
    })

}

loadGlbModel :: proc(using ctx: ^Context) -> ([]Vertex, []u16) {
    // Parse the gltf file
    data, res := cgltf.parse_file({}, "glbs/BoxTextured.gltf");
    if res != .success {
        fmt.eprintf("Failed to parse_file: %v\n", res);
        os.exit(1);
    }

    result := cgltf.load_buffers({}, data, "glbs/BoxTextured.gltf")
    if result != .success {
        fmt.eprintf("Failed to load_buffers: %v\n", result)
    }

    if validationRes := cgltf.validate(data); validationRes != .success {
        fmt.eprintf("Failed to validate: %v\n", validationRes)
    }

    vertices: [dynamic]Vertex;
    indices: [dynamic]u16 ;

    if data == nil || len(data.meshes) == 0 {
        return vertices[:], indices[:]
    }

    loadTextures(ctx, data)
    
    for mesh in data.meshes {
        for primitive in mesh.primitives {
             
            // Process vertex positions
            for i in 0..<len(primitive.attributes) {
                attribute := primitive.attributes[i]
                accessor := attribute.data
                
                // Read position data
                if attribute.type == .position {
                    for j in 0..<accessor.count {
                        position := [3]f32{} 
                        res := cgltf.accessor_read_float(accessor, j, &position[0], 3)
                        if res == false do fmt.eprintln("pos")
                        append(&vertices, Vertex{pos=position})
                    }
                }
                // Read texcoord data
                if attribute.type == .texcoord {
                        for j in 0..<accessor.count {
                            texcoord := [2]f32{}; 
                            res := cgltf.accessor_read_float(accessor, j, &texcoord[0], 2);
                            if res == false {
                                fmt.eprintln("Failed to read texcoord at index: ", j);
                            }
                            vertices[j].texCoord = texcoord; 
                            vertices[j].color = {1.0, 1.0, 1.0}; 
                        }
                }            
            }
        
            // Extract indices
            if primitive.indices != nil {
                index_accessor := primitive.indices;
                for i in 0..<index_accessor.count {
                    idx := cgltf.accessor_read_index(index_accessor, i);
                    append(&indices, cast(u16)idx);
                }
            }
        }
    }

    extractVertexColor(data)
    fmt.println("after extraction")
    fmt.println(len(vertices))
    fmt.println(len(indices))

    cgltf.free(data)

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