package engine

import vk "vendor:vulkan"
import "core:fmt"
import "core:os"

beginCommand :: proc(ctx:^Context) -> vk.CommandBuffer{
    fmt.println("Beginning command buffer...")
    allocInfo := vk.CommandBufferAllocateInfo{
        sType = .COMMAND_BUFFER_ALLOCATE_INFO,
        level = .PRIMARY,
        commandPool = ctx.vulkan.commandPool,
        commandBufferCount = 1
    }

    cmdBuffer : vk.CommandBuffer
    vk.AllocateCommandBuffers(ctx.vulkan.device, &allocInfo, &cmdBuffer)

    beginInfo := vk.CommandBufferBeginInfo{
        sType = .COMMAND_BUFFER_BEGIN_INFO,
        flags = {.ONE_TIME_SUBMIT}
    }

    vk.BeginCommandBuffer(cmdBuffer, &beginInfo)
    return cmdBuffer
}

endCommand :: proc(ctx: ^Context, cmdBuffer: ^vk.CommandBuffer) {
    vk.EndCommandBuffer(cmdBuffer^)
    fmt.println("Ending command buffer...")
    submitInfo := vk.SubmitInfo{
        sType = .SUBMIT_INFO,
        commandBufferCount = 1,
        pCommandBuffers = &cmdBuffer^
    }

    vk.QueueSubmit(ctx.vulkan.graphicsQueue, 1, &submitInfo, {})
    vk.QueueWaitIdle(ctx.vulkan.graphicsQueue)
    vk.FreeCommandBuffers(ctx.vulkan.device, ctx.vulkan.commandPool, 1, &cmdBuffer^)
}