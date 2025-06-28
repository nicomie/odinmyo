package engine

import vk "vendor:vulkan"
import "core:fmt"
import "core:os"
import "core:math/linalg"
import "core:math"
import "core:mem"
import cr "../engine/core"

UBO :: struct{
    model: linalg.Matrix4f32,
    view: linalg.Matrix4f32,
    proj: linalg.Matrix4f32,
    objectId: u32,
    _padding: [12]u8,
}

createUniformBuffers :: proc(using ctx: ^Context) {
    bufferSize := cast(vk.DeviceSize)size_of(UBO)

    uniformBuffers = make([]Buffer, MAX_FRAMES_IN_FLIGHT)
    uniformBuffersMapped = make([]rawptr, MAX_FRAMES_IN_FLIGHT)

    for i in 0..<MAX_FRAMES_IN_FLIGHT {
        createBuffer(ctx, bufferSize, {.UNIFORM_BUFFER}, {.HOST_VISIBLE, .HOST_COHERENT}, &uniformBuffers[i])
        vk.MapMemory(device, uniformBuffers[i].memory, 0, bufferSize, {}, &uniformBuffersMapped[i])
    }
}

updateUniformBuffer :: proc(using ctx: ^Context, currentImage: u32) {


    cam_pos := linalg.Vector3f32{camera.position.x, camera.position.y, camera.position.z}
    target := cam_pos + linalg.Vector3f32{0, 0, -1} 
    up := linalg.Vector3f32{0, 1, 0} 
    view := linalg.matrix4_look_at_f32(
        camera.position.xyz, 
        target,             
        up,                 
        true
    )

    proj := camera.projection
    proj[1][1] *= -1

    angle := math.to_radians_f32(90) * timeContext.timeElapsed
    axis := linalg.Vector3f32{0, 0, 1}
    model := linalg.matrix4_rotate(angle, axis)

    ubo: UBO
    ubo.model = model
    ubo.view = view
    ubo.proj = proj

    mem.copy(uniformBuffersMapped[currentImage], &ubo, size_of(ubo));
}