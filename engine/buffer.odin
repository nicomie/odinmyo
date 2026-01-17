package engine

import "core:encoding/base32"
import vk "vendor:vulkan"
import "core:fmt"
import "core:os"
import "core:mem"
import "core:math/linalg"
import "core:math"


Buffer :: struct{
	buffer: vk.Buffer,
	memory: vk.DeviceMemory,
	length: int,
	size:   vk.DeviceSize,
    mapped_ptr: rawptr
}


FrameBuffer :: struct{
	buffer: []Buffer,
}

createBuffer :: proc(
    using ctx: ^Context, 
    bufferSize: vk.DeviceSize, 
    usage: vk.BufferUsageFlags, 
    properties: vk.MemoryPropertyFlags, 
    buffer: ^Buffer,
    name: string = "not specified",
    data: rawptr = nil,
) {
    using ctx.vulkan
    
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

    fmt.printf("Created buffer %s: %p\n", name, buffer.buffer)
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

createVertexBuffer :: proc(using ctx: ^Context, vertices: []$T) -> ^Buffer {
    using ctx.vulkan
    buffer := new(Buffer)
    buffer.length = len(vertices)
    buffer.size = cast(vk.DeviceSize)(len(vertices) * size_of(T))
    
    staging: Buffer 
    createBuffer(ctx, buffer.size, {.TRANSFER_SRC}, {.HOST_VISIBLE, .HOST_COHERENT}, 
        &staging, "vStaging", raw_data(vertices))
    
    createBuffer(ctx, buffer.size, {.VERTEX_BUFFER, .TRANSFER_DST}, 
        {.DEVICE_LOCAL}, buffer, "vBuffer")
    copyBuffer(ctx, staging, buffer^, buffer.size)

    destroyBuffer("vStaging", ctx.vulkan.device, staging)
    return buffer
}

createIndexBuffer :: proc(using ctx: ^Context, indices: []u32) -> ^Buffer{
    using ctx.vulkan
    buffer := new(Buffer)
    buffer.length = len(indices)
    buffer.size = cast(vk.DeviceSize)(len(indices) * size_of(indices[0]))

    staging: Buffer 
    createBuffer(ctx, buffer.size, {.TRANSFER_SRC}, {.HOST_VISIBLE, .HOST_COHERENT}, &staging,
    "indexStaging")

    data: rawptr 
    vk.MapMemory(device, staging.memory, 0, buffer.size, {}, &data)
    mem.copy(data, raw_data(indices), cast(int)buffer.size)
    vk.UnmapMemory(device, staging.memory)

    createBuffer(ctx ,buffer.size, {.TRANSFER_DST, .INDEX_BUFFER}, {.DEVICE_LOCAL}, buffer, "iBuffer")
    copyBuffer(ctx, staging, buffer^, buffer.size)

    destroyBuffer("indexStaging", ctx.vulkan.device, staging)

    return buffer
}

createCommandBuffers :: proc(using ctx: ^Context) {
    using ctx.vulkan
    using ctx.id
    allocInfo: vk.CommandBufferAllocateInfo
    allocInfo.sType = .COMMAND_BUFFER_ALLOCATE_INFO
    allocInfo.commandPool = commandPool 
    allocInfo.level = .PRIMARY
    allocInfo.commandBufferCount = MAX_FRAMES_IN_FLIGHT

    if vk.AllocateCommandBuffers(device, &allocInfo, &ctx.frames[0].commandBuffers) != .SUCCESS {
        fmt.eprintln("failed to create command buffer")
        os.exit(1)
    }

    if vk.AllocateCommandBuffers(device, &allocInfo, &ctx.frames[0].idCommandBuffer) != .SUCCESS {
        fmt.eprintln("failed to create command buffer")
        os.exit(1)
    }
}

recordIdBuffer :: proc(using ctx: ^Context, buffer: vk.CommandBuffer) {
    using ctx.platform
    using ctx.sc
    using ctx.pipe
    using ctx.resource
    using ctx.id
    using ctx.scene
    beginInfo := vk.CommandBufferBeginInfo{
        sType = .COMMAND_BUFFER_BEGIN_INFO,
        flags = {.ONE_TIME_SUBMIT}
    }
    checkVk(vk.BeginCommandBuffer(buffer, &beginInfo))

    barrier := vk.ImageMemoryBarrier{
        sType = .IMAGE_MEMORY_BARRIER,
        oldLayout = .UNDEFINED, 
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

 
    // render

    vk.CmdEndRenderPass(buffer)

    vk.EndCommandBuffer(buffer)

}

destroyBuffer :: proc(name: string, device: vk.Device, buf: Buffer) {
    fmt.printf("Destroying buffer %s: %p\n", name, buf.buffer)
    vk.DestroyBuffer(device, buf.buffer, nil)
    vk.FreeMemory(device, buf.memory, nil)
}

recordCommandBuffer :: proc(using ctx: ^Context, buffer: vk.CommandBuffer, imageIndex: u32) -> (lastPass: bool, b: vk.CommandBuffer) {
    using ctx.sc
    using ctx.pipe
    using ctx.resource
    using ctx.scene

    beginInfo: vk.CommandBufferBeginInfo
    beginInfo.sType = .COMMAND_BUFFER_BEGIN_INFO
    beginInfo.pInheritanceInfo = nil

    checkVk(vk.BeginCommandBuffer(buffer, &beginInfo))

    renderPassInfo: vk.RenderPassBeginInfo 
    renderPassInfo.sType = .RENDER_PASS_BEGIN_INFO
    renderPassInfo.renderPass = renderPass
    renderPassInfo.framebuffer = swapchain.attachments.framebuffers[imageIndex]
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

    vk.CmdBindDescriptorSets(buffer, vk.PipelineBindPoint.GRAPHICS,meshPipelineLayout, 
                        0, 1, &descriptorSets[currentFrame], 0, nil);

                    

    for &o in meshObjects {
        mesh := meshes[o.meshIndex]


        vertexBuffers := [?]vk.Buffer{mesh.vertexBuffer.buffer}
        offsets := [?]vk.DeviceSize{0}

        vk.CmdBindVertexBuffers(buffer, 0, 1, &vertexBuffers[0], &offsets[0])
        vk.CmdBindIndexBuffer(buffer, mesh.indexBuffer.buffer, 0, .UINT32)

        vk.CmdPushConstants(
            buffer, 
            meshPipelineLayout,
            {.VERTEX}, 
            0, 
            size_of(Mat4), 
            &o.worldTransform
        )

        for primitive in mesh.primitives {
            matIndex := primitive.materialIndex
            vk.CmdBindDescriptorSets(buffer, .GRAPHICS, meshPipelineLayout, 1, 1, 
                &materials[matIndex].descriptorSets[currentFrame], 0, nil)
            vk.CmdDrawIndexed(buffer, cast(u32)primitive.indexCount, 1, cast(u32)primitive.firstIndex, primitive.firstVertex, 0)

        }
    }

    return false, buffer
}

recordUICommandBuffer :: proc(using ctx: ^Context, buffer: vk.CommandBuffer, imageIndex: u32) -> (lastPass: bool, b: vk.CommandBuffer) {
    using ctx.sc
    using ctx.pipe
    using ctx.ui
    using ctx.resource

    vk.CmdBindPipeline(buffer, .GRAPHICS, pipelines["ui"])
    vk.CmdBindDescriptorSets(buffer, .GRAPHICS, uiPipelineLayout, 0, 1, &uiDescriptorSets[currentFrame], 0, nil)

    for &element in elements {
        screen_size := Vec2{f32(swapchain.extent.width), f32(swapchain.extent.height)}
        vk.CmdPushConstants(
            buffer,
            uiPipelineLayout,
            {.VERTEX, .FRAGMENT},
            0,                 
            size_of(Vec2), 
            &screen_size,
        )

        if &element.vertex_buffer^ != nil {
            vertexBuffers := [?]vk.Buffer{element.vertex_buffer.buffer}
            offsets := [?]vk.DeviceSize{0}
            vk.CmdBindVertexBuffers(buffer, 0, 1, raw_data(vertexBuffers[:]), raw_data(offsets[:]))
            vk.CmdDraw(buffer, u32(element.vertex_buffer.length), 1, 0, 0)
        }
    }

    vk.CmdEndRenderPass(buffer)
    
    if vk.EndCommandBuffer(buffer) != .SUCCESS {
        fmt.eprintln("failed to end command buffer")
        return false, nil
    }

    return true, buffer
}

copyBufferToImage :: proc(using ctx: ^Context, buffer: vk.Buffer, w,h : u32, texture: ^Texture) {
    using ctx.resource
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

    vk.CmdCopyBufferToImage(cmdBuffer, buffer, texture.handle.texture, .TRANSFER_DST_OPTIMAL, 1, &region)
}