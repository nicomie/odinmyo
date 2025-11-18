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
        createBuffer(ctx, bufferSize, {.UNIFORM_BUFFER}, {.HOST_VISIBLE, .HOST_COHERENT}, 
            &uniformBuffers[i], fmt.tprintf("ubo%d", i))
        vk.MapMemory(device, uniformBuffers[i].memory, 0, bufferSize, {}, &uniformBuffersMapped[i])
    }
}   

updateUniformBuffer :: proc(using ctx: ^Context, currentImage: u32) {
    using ctx.platform
    using ctx.resource
    using ctx.scene
    
    angle := math.to_radians_f32(90) * timeContext.timeElapsed
    axis := Vec3{0, 0, 1}
    model := linalg.matrix4_rotate(angle, axis)
    
    for &mesh in meshes {
        //mesh.transform = linalg.MATRIX4F32_IDENTITY
    }
    
    camera := camera_system_get_active(&cameraSystem)

    // DEBUG: Check if matrices are valid
    fmt.printf("=== UBO UPDATE ===\n")
    fmt.printf("Camera type: %v\n", camera.type)
    fmt.printf("Camera position: %v\n", camera.position)
    
    // Check if view matrix is all zeros
    is_view_zero := true
    is_proj_zero := true
    
    for i in 0..<4 {
        for j in 0..<4 {
            if camera.view[i][j] != 0 { is_view_zero = false }
            if camera.projection[i][j] != 0 { is_proj_zero = false }
        }
    }
    
    fmt.printf("View matrix all zeros: %v\n", is_view_zero)
    fmt.printf("Projection matrix all zeros: %v\n", is_proj_zero)
    
    if is_view_zero {
        fmt.printf("WARNING: View matrix is all zeros!\n")
        // Create a simple view matrix as fallback
        camera.view = linalg.matrix4_look_at_f32(
            {0, 0, 5},  // eye position
            {0, 0, 0},  // target
            {0, 1, 0}   // up
        )
    }

    ubo: UBO
    ubo.view = camera.view
    ubo.proj = camera.projection

    // DEBUG: Print first row of matrices to verify they're reasonable
    fmt.printf("View[0]: [%.2f, %.2f, %.2f, %.2f]\n", 
        ubo.view[0][0], ubo.view[0][1], ubo.view[0][2], ubo.view[0][3])
    fmt.printf("Proj[0]: [%.2f, %.2f, %.2f, %.2f]\n", 
        ubo.proj[0][0], ubo.proj[0][1], ubo.proj[0][2], ubo.proj[0][3])
    fmt.printf("==================\n")

    mem.copy(uniformBuffersMapped[currentImage], &ubo, size_of(ubo))
}