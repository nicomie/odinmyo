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
    using ctx.scene

    sys := &ctx.scene.cameraSystem

    bufferSize := cast(vk.DeviceSize)size_of(UBO)

    sys.uniformBuffers = make([]Buffer, MAX_FRAMES_IN_FLIGHT)
    sys.uniformBuffersMapped = make([]rawptr, MAX_FRAMES_IN_FLIGHT)

    for i in 0..<MAX_FRAMES_IN_FLIGHT {
        createBuffer(ctx, bufferSize, {.UNIFORM_BUFFER}, {.HOST_VISIBLE, .HOST_COHERENT}, 
            &sys.uniformBuffers[i], fmt.tprintf("ubo%d", i))
        vk.MapMemory(device, sys.uniformBuffers[i].memory, 0, bufferSize, {}, &sys.uniformBuffersMapped[i])
    }
}   

updateUniformBuffer :: proc(using ctx: ^Context, currentImage: u32) {
    using ctx.platform
    using ctx.resource
    using ctx.scene
        
    camera := camera_system_get_active(&cameraSystem)

    ubo: UBO
    ubo.view = camera.view
    ubo.proj = camera.projection

    mem.copy(cameraSystem.uniformBuffersMapped[currentImage], &ubo, size_of(ubo))
}