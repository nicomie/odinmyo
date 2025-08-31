package engine

import vk "vendor:vulkan"
import "core:fmt"
import "core:os"

handleMouseClick :: proc(using ctx: ^Context, x, y: i32) {
    using ctx.platform
    using ctx.vulkan
    clickPending = true
    clickX = x
    clickY = y

    submitInfo := vk.SubmitInfo{
        sType = .SUBMIT_INFO,
        commandBufferCount = 1,
        pCommandBuffers = &idCommandBuffer[currentFrame],
    }
    vk.QueueSubmit(graphicsQueue, 1, &submitInfo, {})
}

processClick :: proc(using ctx: ^Context) {
    using ctx.platform
    using ctx.vulkan
    // Only copy the clicked pixel
    cmdBuffer := beginCommand(ctx)
    
    region := vk.BufferImageCopy{
        imageSubresource = {
            aspectMask = {.COLOR},
            mipLevel = 0,
            baseArrayLayer = 0,
            layerCount = 1
        },
        imageOffset = {clickX, clickY, 0},
        imageExtent = {1, 1, 1}
    }

    vk.CmdCopyImageToBuffer(cmdBuffer,
        idImage.image.texture, .TRANSFER_SRC_OPTIMAL,
        idStagingBuffer.buffer, 1, &region)

    endCommand(ctx, &cmdBuffer)

    // Read back the pixel data
    data: rawptr
    vk.MapMemory(device, idStagingBuffer.memory, 0, 4, {}, &data)
    pixels := cast([^]u8)data
    clickedId := u32(pixels[0]) << 16 | u32(pixels[1]) << 8 | u32(pixels[2])
    vk.UnmapMemory(device, idStagingBuffer.memory)
    
    fmt.printf("Clicked object ID: %d at (%d, %d)\n", clickedId, clickX, clickY)
    clickPending = false
}