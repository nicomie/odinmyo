package app

import vk "vendor:vulkan"
import "core:os"
import "core:fmt"


begin_command :: proc(using r: ^Renderer) -> (cmd: vk.CommandBuffer, err: vk.Result) {
    alloc_info := vk.CommandBufferAllocateInfo{
        sType = .COMMAND_BUFFER_ALLOCATE_INFO,
        commandPool = r.commandPool,
        level = .PRIMARY,
        commandBufferCount = 1,
    }

    if vk.AllocateCommandBuffers(r.device, &alloc_info, &cmd) != .SUCCESS {
        return {}, .ERROR_OUT_OF_HOST_MEMORY
    }

    begin_info := vk.CommandBufferBeginInfo{
        sType = .COMMAND_BUFFER_BEGIN_INFO,
        flags = {.ONE_TIME_SUBMIT},
    }

    if vk.BeginCommandBuffer(cmd, &begin_info) != .SUCCESS {
        vk.FreeCommandBuffers(r.device, r.commandPool, 1, &cmd)
        return {}, .ERROR_OUT_OF_HOST_MEMORY
    }

    return cmd, .SUCCESS
}

end_command :: proc(
    using r: ^Renderer,
    cmd: ^vk.CommandBuffer,
    wait_for_idle: bool = true,
) -> vk.Result {
    if vk.EndCommandBuffer(cmd^) != .SUCCESS {
        return .ERROR_OUT_OF_HOST_MEMORY
    }

    submit_info := vk.SubmitInfo{
        sType = .SUBMIT_INFO,
        commandBufferCount = 1,
        pCommandBuffers = &cmd^,
    }

    if vk.QueueSubmit(r.graphics_queue, 1, &submit_info, {}) != .SUCCESS {
        return .ERROR_OUT_OF_HOST_MEMORY
    }

    if wait_for_idle {
        if vk.QueueWaitIdle(r.graphics_queue) != .SUCCESS {
            return .ERROR_OUT_OF_HOST_MEMORY
        }
    }

    vk.FreeCommandBuffers(r.device, r.commandPool, 1, cmd)
    return .SUCCESS
}
