package engine 

import "core:math"
import "core:math/linalg"
import "core:mem"
import vk "vendor:vulkan"

MOVE_SPEED :f32: 30

Camera :: struct {
    projection: linalg.Matrix4x4f32,
    position: linalg.Vector4f32,
    view: linalg.Matrix4x4f32,
    model: linalg.Matrix4x4f32,
    velocity: linalg.Vector3f32,
    acceleration: f32,
    max_speed: f32,

    // Orbit
    target:   linalg.Vector3f32,
    yaw:      f32,
    pitch:    f32,
    distance: f32, 
}

CameraUBO :: struct {
    view: linalg.Matrix4x4f32,
    proj: linalg.Matrix4x4f32,
}

initCamera :: proc(using ctx: ^Context) {
    camera.position = linalg.Vector4f32{0.0, 0.0, 5.0, 1.0}

    target := linalg.Vector3f32{0, 0, 0}
    up := linalg.Vector3f32{0, 1, 0}
    camera.acceleration = 15.0
    camera.max_speed = 5.0
    camera.velocity = {0, 0, 0}

    camera.view = linalg.matrix4_look_at_f32(
        camera.position.xyz,
        target,
        up,
        true
    )

    aspect_ratio :f32= 1280.0 / 720.0 
    camera.projection = linalg.matrix4_perspective(
        math.to_radians_f32(60.0), 
        aspect_ratio,
        0.1,                     
        100.0,                   
        true)
    camera.projection[1][1] *= -1

    camera.distance = 5.0
}
