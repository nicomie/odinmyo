package app 

import vk "vendor:vulkan"
import "core:time"
import "core:math"
import "core:math/linalg"
import "core:mem"


UBO :: struct{
    model: linalg.Matrix4f32,
    view: linalg.Matrix4f32,
    proj: linalg.Matrix4f32,
    objectId: u32,
    _padding: [12]u8,
}

Camera :: struct {
    projection: linalg.Matrix4x4f32,
    position: linalg.Vector4f32,
    view: linalg.Matrix4x4f32,
    model: linalg.Matrix4x4f32,
    uniform_buffers: []Buffer,
    uniform_buffers_mapped: []rawptr,
}

init_camera :: proc(r: ^Renderer) {
    r.camera.position = {5, 5, 5, 1}
    r.camera.projection = linalg.matrix4_perspective(
        math.to_radians_f32(60.0),
        cast(f32)r.swapchain.extent.width / cast(f32)r.swapchain.extent.height,
        0.1,
        1000.0,
        true
    )
    r.camera.projection[1][1] *= -1  

    bufferSize := get_size_type(UBO)
    r.camera.uniform_buffers = make([]Buffer, MAX_FRAMES_IN_FLIGHT)
    r.camera.uniform_buffers_mapped = make([]rawptr, MAX_FRAMES_IN_FLIGHT)

    for i in 0..<MAX_FRAMES_IN_FLIGHT {
        create_buffer(r, bufferSize, {.UNIFORM_BUFFER}, {.HOST_VISIBLE, .HOST_COHERENT}, &r.camera.uniform_buffers[i])
        vk.MapMemory(r.device, r.camera.uniform_buffers[i].memory, 0, bufferSize, {}, &r.camera.uniform_buffers_mapped[i])
    }
}

update_camera :: proc(
    r: ^Renderer,
    current_image: u32
) -> vk.Result {
    current := time.now()
    time_elapsed := cast(f32)time.duration_seconds(time.diff(r.start, current))
    
    movement := math.sin(time_elapsed) * 1.0
    translation := linalg.matrix4_translate(linalg.Vector3f32{movement, 0, 0})
    angle := math.to_radians_f32(90) * time_elapsed
    axis := linalg.Vector3f32{0, 0, 1}
    r.camera.model = translation * linalg.matrix4_rotate(angle, axis)

    ubo := UBO{
        model = r.camera.model,
        view = linalg.matrix4_look_at_f32(
            linalg.Vector3f32{5, 5, 5},
            linalg.Vector3f32{0, 0, 0},
            linalg.Vector3f32{0, 0, 1},
            true
        ),
        proj = r.camera.projection,
    }

    mem.copy(
        r.camera.uniform_buffers_mapped[current_image],
        &ubo,
        size_of(ubo)
    )

    return .SUCCESS
}