package engine

import vk "vendor:vulkan"
import "core:fmt"
import "core:os"
import "core:mem"
import "core:math/linalg"
import "core:math"


Buffer :: struct
{
	buffer: vk.Buffer,
	memory: vk.DeviceMemory,
	length: int,
	size:   vk.DeviceSize,
}

createBuffer :: proc(
    using ctx: ^Context, 
    bufferSize: vk.DeviceSize, 
    usage: vk.BufferUsageFlags, 
    properties: vk.MemoryPropertyFlags, 
    buffer: ^Buffer,
    data: rawptr = nil
) {
    
    bufferInfo := vk.BufferCreateInfo{
        sType = .BUFFER_CREATE_INFO,
        size = bufferSize,
        usage = usage,
        sharingMode = .EXCLUSIVE,
    }
    checkVk(vk.CreateBuffer(device, &bufferInfo, nil, &buffer.buffer))

    memRequirements: vk.MemoryRequirements
    vk.GetBufferMemoryRequirements(device, buffer.buffer, &memRequirements)

    allocInfo := vk.MemoryAllocateInfo{
        sType = .MEMORY_ALLOCATE_INFO,
        allocationSize = memRequirements.size,
        memoryTypeIndex = findMemType(physicalDevice, memRequirements.memoryTypeBits, properties)
    }

    checkVk(vk.AllocateMemory(device, &allocInfo, nil, &buffer.memory))
    checkVk(vk.BindBufferMemory(device, buffer.buffer, buffer.memory, 0))

    if data != nil {
        ptr: rawptr
        checkVk(vk.MapMemory(device, buffer.memory, 0, bufferSize, {}, &ptr))
        mem.copy(ptr, data, int(bufferSize))
        vk.UnmapMemory(device, buffer.memory)
    }
}

copyBuffer :: proc(using ctx: ^Context, src, dst: Buffer, size: vk.DeviceSize) {
    cmdBuffer := beginCommand(ctx)
    defer endCommand(ctx, &cmdBuffer)
    copyRegion := vk.BufferCopy{
        srcOffset = 0,
        dstOffset = 0,
        size = size,
    }
    vk.CmdCopyBuffer(cmdBuffer, src.buffer, dst.buffer, 1, &copyRegion)
}

createVertexBuffer :: proc(using ctx: ^Context, vertices: []Vertex) -> Buffer {
    buffer: Buffer
    buffer.length = len(vertices)
    buffer.size = cast(vk.DeviceSize)(len(vertices) * size_of(Vertex))
    
    staging: Buffer 
    createBuffer(ctx, buffer.size, {.TRANSFER_SRC}, {.HOST_VISIBLE, .HOST_COHERENT}, &staging, raw_data(vertices))
    
    createBuffer(ctx, buffer.size, {.VERTEX_BUFFER, .TRANSFER_DST}, {.DEVICE_LOCAL}, &buffer)
    copyBuffer(ctx, staging, buffer, buffer.size)

    vk.DestroyBuffer(device, staging.buffer, nil)
    vk.FreeMemory(device, staging.memory, nil)

    return buffer
}

createIndexBuffer :: proc(using ctx: ^Context, indices: []u16) -> Buffer{
    buffer: Buffer
    buffer.length = len(indices)
    buffer.size = cast(vk.DeviceSize)(len(indices) * size_of(indices[0]))

    staging: Buffer 
    createBuffer(ctx, buffer.size, {.TRANSFER_SRC}, {.HOST_VISIBLE, .HOST_COHERENT}, &staging)

    data: rawptr 
    vk.MapMemory(device, staging.memory, 0, buffer.size, {}, &data)
    mem.copy(data, raw_data(indices), cast(int)buffer.size)
    vk.UnmapMemory(device, staging.memory)

    createBuffer(ctx ,buffer.size, {.TRANSFER_DST, .INDEX_BUFFER}, {.DEVICE_LOCAL}, &buffer)
    copyBuffer(ctx, staging, buffer, buffer.size)

    vk.DestroyBuffer(device, staging.buffer, nil)
    vk.FreeMemory(device, staging.memory, nil)

    return buffer
}

createCommandBuffers :: proc(using ctx: ^Context) {
    allocInfo: vk.CommandBufferAllocateInfo
    allocInfo.sType = .COMMAND_BUFFER_ALLOCATE_INFO
    allocInfo.commandPool = commandPool 
    allocInfo.level = .PRIMARY
    allocInfo.commandBufferCount = MAX_FRAMES_IN_FLIGHT

    if vk.AllocateCommandBuffers(device, &allocInfo, &commandBuffers[0]) != .SUCCESS {
        fmt.eprintln("failed to create command buffer")
        os.exit(1)
    }

    if vk.AllocateCommandBuffers(device, &allocInfo, &idCommandBuffer[0]) != .SUCCESS {
        fmt.eprintln("failed to create command buffer")
        os.exit(1)
    }
}

recordIdBuffer :: proc(using ctx: ^Context, buffer: vk.CommandBuffer) {
    beginInfo := vk.CommandBufferBeginInfo{
        sType = .COMMAND_BUFFER_BEGIN_INFO,
        flags = {.ONE_TIME_SUBMIT}
    }
    checkVk(vk.BeginCommandBuffer(buffer, &beginInfo))

    barrier := vk.ImageMemoryBarrier{
        sType = .IMAGE_MEMORY_BARRIER,
        oldLayout = .UNDEFINED, // Or whatever layout it's currently in
        newLayout = .COLOR_ATTACHMENT_OPTIMAL,
        image = idImage.image.texture,
        subresourceRange = {
            aspectMask = {.COLOR},
            baseMipLevel = 0,
            levelCount = 1,
            baseArrayLayer = 0,
            layerCount = 1
        },
        srcAccessMask = {},
        dstAccessMask = {.COLOR_ATTACHMENT_WRITE}
    }
    vk.CmdPipelineBarrier(buffer, 
        {.TOP_OF_PIPE}, 
        {.COLOR_ATTACHMENT_OUTPUT},
        {}, 
        0, nil, 0, nil, 1, &barrier)

    clearValues := []vk.ClearValue{
        {color = {float32 = [4]f32{0.0, 0.0, 0.0, 1.0}}}, 
        {depthStencil = {1.0, 0}}
    }
   
    renderPassInfo := vk.RenderPassBeginInfo{
        sType = .RENDER_PASS_BEGIN_INFO,
        renderPass = idRenderPass,
        framebuffer = idFramebuffer,
        renderArea = {
            offset = {0,0},
            extent = swapchain.extent
        },
        clearValueCount = cast(u32)len(clearValues),
        pClearValues = &clearValues[0],
    }

    vk.CmdBeginRenderPass(buffer, &renderPassInfo, .INLINE)

    vk.CmdBindPipeline(buffer, .GRAPHICS, pipelines["id"])
    vk.CmdBindDescriptorSets(buffer, .GRAPHICS, idPipelineLayout, 0, 1, &idDescriptorSets[currentFrame], 0, nil)

 
    for &mesh,i in meshes {
        angle := math.to_radians_f32(90) * timeContext.timeElapsed
        axis := linalg.Vector3f32{0, 0, 1}
        model := linalg.matrix4_rotate(angle, axis)
        mesh.transform = model

        ubo: UBO
        ubo.view = camera.view
        ubo.proj = camera.projection
        
        mem.copy(uniformBuffersMapped[currentFrame], &ubo, size_of(ubo))

        vertexBuffers := [?]vk.Buffer{mesh.vertexBuffer.buffer}
        offsets := [?]vk.DeviceSize{0}

        vk.CmdPushConstants(
            buffer, 
            meshPipelineLayout,
            {.VERTEX}, 
            0, 
            size_of(linalg.Matrix4x4f32), 
            &model
        )

        vk.CmdBindVertexBuffers(buffer, 0, 1, &vertexBuffers[0], &offsets[0])
        vk.CmdBindIndexBuffer(buffer, mesh.indexBuffer.buffer, 0, .UINT16)
        vk.CmdDrawIndexed(buffer, cast(u32)mesh.indexBuffer.length, 1, 0, 0, 0)
    }

    vk.CmdEndRenderPass(buffer)

    vk.EndCommandBuffer(buffer)

}

recordCommandBuffer :: proc(using ctx: ^Context, buffer: vk.CommandBuffer, imageIndex: u32) {
    beginInfo: vk.CommandBufferBeginInfo
    beginInfo.sType = .COMMAND_BUFFER_BEGIN_INFO
    beginInfo.pInheritanceInfo = nil

    checkVk(vk.BeginCommandBuffer(buffer, &beginInfo))

    renderPassInfo: vk.RenderPassBeginInfo 
    renderPassInfo.sType = .RENDER_PASS_BEGIN_INFO
    renderPassInfo.renderPass = renderPass
    renderPassInfo.framebuffer = swapchain.framebuffers[imageIndex]
    renderPassInfo.renderArea.offset = {0, 0}
    renderPassInfo.renderArea.extent = swapchain.extent

    clearValues := []vk.ClearValue{
        {color = {float32 = [4]f32{0.0, 0.0, 0.0, 1.0}}}, 
        {depthStencil = {1.0, 0}}
    }
   
    renderPassInfo.clearValueCount = cast(u32)len(clearValues)
    renderPassInfo.pClearValues = &clearValues[0]
    
    vk.CmdBeginRenderPass(buffer, &renderPassInfo, .INLINE)

    viewport : vk.Viewport
    viewport.x = 0.0
    viewport.y = 0.0
    viewport.width = cast(f32)swapchain.extent.width
    viewport.height = cast(f32)swapchain.extent.height
    viewport.minDepth = 0.0
    viewport.maxDepth = 1.0
    vk.CmdSetViewport(buffer, 0, 1, &viewport)

    scissor : vk.Rect2D 
    scissor.offset = {0, 0}
    scissor.extent = swapchain.extent
    vk.CmdSetScissor(buffer, 0, 1, &scissor)

    vk.CmdBindPipeline(buffer, .GRAPHICS, pipelines["mesh"])

    vk.CmdBindDescriptorSets(buffer, vk.PipelineBindPoint.GRAPHICS,
                        meshPipelineLayout, 
                        0, 1, &descriptorSets[currentFrame], 0, nil);

    for &mesh in meshes {
    
        vertexBuffers := [?]vk.Buffer{mesh.vertexBuffer.buffer}
        offsets := [?]vk.DeviceSize{0}


        vk.CmdPushConstants(
            buffer, 
            meshPipelineLayout,
            {.VERTEX}, 
            0, 
            size_of(linalg.Matrix4x4f32), 
            &mesh.transform
        )

        vk.CmdBindVertexBuffers(buffer, 0, 1, &vertexBuffers[0], &offsets[0])
        vk.CmdBindIndexBuffer(buffer, mesh.indexBuffer.buffer, 0, .UINT16)
        vk.CmdDrawIndexed(buffer, cast(u32)mesh.indexBuffer.length, 1, 0, 0, 0)
    }

    vk.CmdEndRenderPass(buffer)

    checkVk(vk.EndCommandBuffer(buffer))
}

copyBufferToImage :: proc(using ctx: ^Context, buffer: vk.Buffer, w,h : u32) {
    cmdBuffer := beginCommand(ctx)
    defer endCommand(ctx, &cmdBuffer)

    region : vk.BufferImageCopy
    region.bufferOffset = 0
    region.bufferRowLength = 0
    region.bufferImageHeight = 0
    region.imageSubresource.aspectMask = {.COLOR}
    region.imageSubresource.mipLevel = 0
    region.imageSubresource.baseArrayLayer = 0
    region.imageSubresource.layerCount = 1
    region.imageOffset = {0,0,0}
    region.imageExtent = {w,h,1}

    vk.CmdCopyBufferToImage(cmdBuffer, buffer, texture.texture, .TRANSFER_DST_OPTIMAL, 1, &region)
}