package engine

import vk "vendor:vulkan"
import "core:fmt"
import "core:os"
import "core:math/linalg"
import "core:math"
import "core:mem"
import cr "../engine/core"

CameraUBO :: struct{
    view: linalg.Matrix4f32,
    proj: linalg.Matrix4f32,
}

createUniformBuffers :: proc(using ctx: ^Context) {

    initFrameBuffer(ctx, &ctx.scene.cameraSystem.uniformBuffers, CameraUBO)
}   

initFrameBuffer :: proc(ctx: ^Context, buffer: ^FrameBuffer, $T: typeid) {
    using ctx.vulkan
    using ctx.resource
    using ctx.scene

    bufferSize := cast(vk.DeviceSize)size_of(T)

    buffer.buffer = make([]Buffer, MAX_FRAMES_IN_FLIGHT)

    for i in 0..<MAX_FRAMES_IN_FLIGHT{
        createBuffer(ctx, bufferSize, {.UNIFORM_BUFFER}, {.HOST_VISIBLE, .HOST_COHERENT}, 
            &buffer.buffer[i], fmt.tprintf("ubo%d", i))
        vk.MapMemory(device, buffer.buffer[i].memory, 0, bufferSize, {}, &buffer.buffer[i].mapped_ptr)
    }
}

updateUniformBuffer :: proc(using ctx: ^Context, currentImage: u32) {
    using ctx.platform
    using ctx.resource
    using ctx.scene
        
    camera := camera_system_get_active(&cameraSystem)

    ubo: CameraUBO = {
        view = camera.view,
        proj = camera.projection
    }

    mem.copy(cameraSystem.uniformBuffers.buffer[currentImage].mapped_ptr, &ubo, size_of(ubo))
}