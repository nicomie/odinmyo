package engine

import vk "vendor:vulkan"
import "core:fmt"
import "core:os"
import "core:math/linalg"
import "core:math"
import "core:mem"
import cr "../engine/core"

UBO :: struct{
    view: linalg.Matrix4f32,
    proj: linalg.Matrix4f32,
}

createUniformBuffers :: proc(using ctx: ^Context) {
    using ctx.vulkan
    using ctx.resource
    bufferSize := cast(vk.DeviceSize)size_of(UBO)

    uniformBuffers = make([]Buffer, MAX_FRAMES_IN_FLIGHT)
    uniformBuffersMapped = make([]rawptr, MAX_FRAMES_IN_FLIGHT)

    for i in 0..<MAX_FRAMES_IN_FLIGHT {
        createBuffer(ctx, bufferSize, {.UNIFORM_BUFFER}, {.HOST_VISIBLE, .HOST_COHERENT}, &uniformBuffers[i])
        vk.MapMemory(device, uniformBuffers[i].memory, 0, bufferSize, {}, &uniformBuffersMapped[i])
    }
}

updateUniformBuffer :: proc(using ctx: ^Context, currentImage: u32) {
    using ctx.platform
    using ctx.resource
    using ctx.scene
    angle := math.to_radians_f32(90) * timeContext.timeElapsed
    axis := linalg.Vector3f32{0, 0, 1}
    model := linalg.matrix4_rotate(angle, axis)
    
    for &mesh in meshes {
        mesh.transform = linalg.MATRIX4F32_IDENTITY
    }
    
    ubo: UBO
    ubo.view = camera.view
    ubo.proj = camera.projection

    mem.copy(uniformBuffersMapped[currentImage], &ubo, size_of(ubo))
}