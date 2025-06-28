package engine

import "core:fmt"
import "core:os"
import "core:math/linalg"


Vec4Position :: proc(vec3: [3]f32) -> linalg.Vector4f32 {
    return linalg.Vector4f32{
        vec3[0], vec3[1], vec3[2], 1.0
    }
}

Vec4Direction:: proc(vec3: [3]f32) -> linalg.Vector4f32 {
    return linalg.Vector4f32{
        vec3[0], vec3[1], vec3[2], 0.0
    }
}

Vec3From4 :: proc(vec4: [4]f32) -> linalg.Vector3f32 {
    return linalg.Vector3f32{
        vec4[0], vec4[1], vec4[2]
    }
}