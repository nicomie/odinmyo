package engine 

import "core:math"
import "core:math/linalg"
import "core:mem"
import vk "vendor:vulkan"
import "core:fmt"

MOVE_SPEED :: 30.0

CameraSystem :: struct {
    cameras: [CameraType]Camera,
    active_camera_type: CameraType,
    previous_camera_type: CameraType,  
    descriptorSets: [MAX_FRAMES_IN_FLIGHT]vk.DescriptorSet,
    uniformBuffers: FrameBuffer,
}

camera_system_init :: proc(system: ^CameraSystem) {
    system.active_camera_type = .Free
    system.previous_camera_type = .Free
}

camera_system_add :: proc(system: ^CameraSystem, camera: Camera) {
    system.cameras[camera.type] = camera
}

camera_system_toggle :: proc(system: ^CameraSystem, target_type: CameraType) {
    if (target_type == .Player) {
        //system.cameras[.Player].position = ctx.meshes[0].
    }
    system.previous_camera_type = system.active_camera_type
    system.active_camera_type = target_type
}

camera_system_get_active :: proc(system: ^CameraSystem) -> ^Camera {
    return &system.cameras[system.active_camera_type]
}

camera_system_toggle_quick :: proc(system: ^CameraSystem) {
    system.active_camera_type, system.previous_camera_type = system.previous_camera_type, system.active_camera_type
}

Camera :: struct {
    type: CameraType,

    projection: Mat4,
    position: Vec4,
    view: Mat4,
    model: Mat4,
    velocity: Vec3,
    acceleration: f32,
    max_speed: f32,

    // Orbit
    target:   Vec3,
    yaw:      f32,
    pitch:    f32,
    distance: f32, 

    is_active: bool,

    free_move_speed: f32,
    free_rotation_speed: f32,

    player_entity_id: u32,
    player_offset: Vec3, 
}

CameraType :: enum {
    Free,
    Player,
    Orbit,
}

freeCameras :: proc(ctx: ^Context) {
    using ctx.vulkan
    sys := ctx.scene.cameraSystem


    for i in 0..<MAX_FRAMES_IN_FLIGHT {
        destroyBuffer(fmt.tprintf("ubo%d", i), device, sys.uniformBuffers.buffer[i])
    }
    delete(sys.uniformBuffers.buffer)
    
}

initCamera :: proc(using ctx: ^Context) {
    using ctx.sc
    using ctx.scene

    camera_system_init(&cameraSystem)

    free_camera := Camera{
        type = .Free,
        is_active = true,
        free_move_speed = 5.0,
        position = {0, 0, 5, 1},
        target = {0, 0, 0},
        distance = 5.0,
        yaw = 0.0,
        pitch = 0.0,
        view = linalg.matrix4_look_at_f32(
        {0, 0, 5},  // Looking from (0,0,5)
        {0, 0, 0},  // Looking at origin
        {0, 1, 0}   // Up vector
    )
    }

    player_camera := Camera{
        type = .Player,
        is_active = true,
        player_offset = {0, 2, -5},
        position = {0, 2, 5, 1}, 
        target = {0, 0, 0},
        distance = 5.0,
        yaw = 0.0,
        pitch = 0.0,
        view = linalg.matrix4_look_at_f32(
        {0, 2, 5},  // Slightly above
        {0, 0, 0},
        {0, 1, 0}
    )
    }

    aspect_ratio := f32(swapchain.extent.width) / f32(swapchain.extent.height)
    
    // Set projections for both cameras
    free_camera.projection = linalg.matrix4_perspective(
        math.to_radians_f32(60.0), 
        aspect_ratio,
        0.1,                     
        100.0,                   
    )
    free_camera.projection[1][1] *= -1  

    player_camera.projection = free_camera.projection

    camera_system_add(&cameraSystem, free_camera)
    camera_system_add(&cameraSystem, player_camera)

    // Initialize camera position
    updateCameraPosition(ctx)
}

updateCameraPosition :: proc(using ctx: ^Context) {
    camera := camera_system_get_active(&ctx.scene.cameraSystem)

    q_yaw := linalg.quaternion_angle_axis_f32(-camera.yaw, Vec3{0, 1, 0})
    q_pitch := linalg.quaternion_angle_axis_f32(-camera.pitch, Vec3{1, 0, 0})
    orientation := linalg.mul(q_yaw, q_pitch)

    // Offset from the target along rotated Z-axis
    base_offset := Vec3{0, 0, camera.distance}
    rotated_offset := linalg.quaternion_mul_vector3(orientation, base_offset)

    pos := camera.target + rotated_offset 
    camera.position = {pos.x, pos.y, pos.z, 1.0}

    // Create camera basis vectors from orientation
    forward := linalg.normalize(camera.target - pos)
    right := linalg.normalize(linalg.quaternion_mul_vector3(orientation, Vec3{1, 0, 0}))
    up := linalg.normalize(linalg.cross(right, forward))

    camera.view = linalg.matrix4_look_at_f32(pos, camera.target, up)
}