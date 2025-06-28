package engine

import vk "vendor:vulkan"
import "core:fmt"
import "core:os"

beginCommand :: proc(using ctx:^Context) -> vk.CommandBuffer{
    allocInfo := vk.CommandBufferAllocateInfo{
        sType = .COMMAND_BUFFER_ALLOCATE_INFO,
        level = .PRIMARY,
        commandPool = commandPool,
        commandBufferCount = 1
    }

    cmdBuffer : vk.CommandBuffer
    vk.AllocateCommandBuffers(device, &allocInfo, &cmdBuffer)

    beginInfo := vk.CommandBufferBeginInfo{
        sType = .COMMAND_BUFFER_BEGIN_INFO,
        flags = {.ONE_TIME_SUBMIT}
    }

    vk.BeginCommandBuffer(cmdBuffer, &beginInfo)
    return cmdBuffer
}

endCommand :: proc(using ctx: ^Context, cmdBuffer: ^vk.CommandBuffer) {
    vk.EndCommandBuffer(cmdBuffer^)

    submitInfo := vk.SubmitInfo{
        sType = .SUBMIT_INFO,
        commandBufferCount = 1,
        pCommandBuffers = &cmdBuffer^
    }

    vk.QueueSubmit(graphicsQueue, 1, &submitInfo, {})
    vk.QueueWaitIdle(graphicsQueue)
    vk.FreeCommandBuffers(device, commandPool, 1, &cmdBuffer^)
}