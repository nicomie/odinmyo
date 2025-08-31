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

initCamera :: proc(using ctx: ^Context) {
    using ctx.sc
    using ctx.scene
    camera.target = linalg.Vector3f32{0, 0, 0}
    camera.distance = 5.0 
    camera.yaw = 0.0
    camera.pitch = 0.0
    
    updateCameraPosition(ctx)

    aspect_ratio := f32(swapchain.extent.width) / f32(swapchain.extent.height)
    camera.projection = linalg.matrix4_perspective(
        math.to_radians_f32(60.0), 
        aspect_ratio,
        0.1,                     
        100.0,                   
        true)
    camera.projection[1][1] *= -1  
}

updateCameraPosition :: proc(using ctx: ^Context) {
    using ctx.scene
    q_yaw := linalg.quaternion_angle_axis_f32(-camera.yaw, linalg.Vector3f32{0, 1, 0})
    q_pitch := linalg.quaternion_angle_axis_f32(-camera.pitch, linalg.Vector3f32{1, 0, 0})
    orientation := linalg.mul(q_yaw, q_pitch)

    // Offset from the target along rotated Z-axis
    base_offset := linalg.Vector3f32{0, 0, camera.distance}
    rotated_offset := linalg.quaternion_mul_vector3(orientation, base_offset)

    pos := camera.target + rotated_offset 
    camera.position = linalg.Vector4f32{pos.x, pos.y, pos.z, 1.0}

    // Create camera basis vectors from orientation
    forward := linalg.normalize(camera.target - pos)
    right := linalg.normalize(linalg.quaternion_mul_vector3(orientation, linalg.Vector3f32{1, 0, 0}))
    up := linalg.normalize(linalg.cross(right, forward))  // Consistent up

    camera.view = linalg.matrix4_look_at_f32(pos, camera.target, up, true)
}
