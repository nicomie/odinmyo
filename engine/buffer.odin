package engine

import "core:encoding/base32"
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
    mapped_ptr: rawptr
}

createBuffer :: proc(
    ctx: ^Context, 
    bufferSize: vk.DeviceSize, 
    usage: vk.BufferUsageFlags, 
    properties: vk.MemoryPropertyFlags, 
    buffer: ^Buffer,
    name: string = "not specified",
    data: rawptr = nil,
) {
    device := ctx.vulkan.device
    
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
        memoryTypeIndex = findMemType(ctx.vulkan.physicalDevice, memRequirements.memoryTypeBits, properties)
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

copyBuffer :: proc(ctx: ^Context, src, dst: Buffer, size: vk.DeviceSize) {
    cmdBuffer := beginCommand(ctx)
    defer endCommand(ctx, &cmdBuffer)
    copyRegion := vk.BufferCopy{
        srcOffset = 0,
        dstOffset = 0,
        size = size,
    }
    vk.CmdCopyBuffer(cmdBuffer, src.buffer, dst.buffer, 1, &copyRegion)
}

createVertexBuffer :: proc(ctx: ^Context, vertices: []$T) -> ^Buffer {
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

createIndexBuffer :: proc(ctx: ^Context, indices: []u32) -> ^Buffer{
    device := ctx.vulkan.device

    buffer := new(Buffer)
    buffer.length = len(indices)
    buffer.size = cast(vk.DeviceSize)(len(indices) * size_of(indices[0]))

    staging: Buffer 
    createBuffer(ctx, buffer.size, {.TRANSFER_SRC}, {.HOST_VISIBLE, .HOST_COHERENT}, &staging,
    "indexStaging")

    data: rawptr 
    vk.MapMemory(ctx.vulkan.device, staging.memory, 0, buffer.size, {}, &data)
    mem.copy(data, raw_data(indices), cast(int)buffer.size)
    vk.UnmapMemory(device, staging.memory)

    createBuffer(ctx ,buffer.size, {.TRANSFER_DST, .INDEX_BUFFER}, {.DEVICE_LOCAL}, buffer, "iBuffer")
    copyBuffer(ctx, staging, buffer^, buffer.size)

    destroyBuffer("indexStaging", ctx.vulkan.device, staging)

    return buffer
}

createCommandBuffers :: proc(ctx: ^Context) {
    device := ctx.vulkan.device
    
    allocInfo: vk.CommandBufferAllocateInfo
    allocInfo.sType = .COMMAND_BUFFER_ALLOCATE_INFO
    allocInfo.commandPool = ctx.vulkan.commandPool 
    allocInfo.level = .PRIMARY
    allocInfo.commandBufferCount = MAX_FRAMES_IN_FLIGHT

    for i in 0..<MAX_FRAMES_IN_FLIGHT {
        if vk.AllocateCommandBuffers(device, &allocInfo, &ctx.frames[i].commandBuffer) != .SUCCESS {
            fmt.eprintln("failed to create command buffer")
            os.exit(1)
        }
    }
}

destroyBuffer :: proc(name: string, device: vk.Device, buf: Buffer) {
    fmt.printf("Destroying buffer %s: %p\n", name, buf.buffer)
    vk.DestroyBuffer(device, buf.buffer, nil)
    vk.FreeMemory(device, buf.memory, nil)
}

recordCommandBuffer :: proc(ctx: ^Context, buffer: vk.CommandBuffer, imageIndex: u32) {
    swapchain := &ctx.sc.swapchain

    beginInfo: vk.CommandBufferBeginInfo
    beginInfo.sType = .COMMAND_BUFFER_BEGIN_INFO
    beginInfo.pInheritanceInfo = nil

    checkVk(vk.BeginCommandBuffer(buffer, &beginInfo))

    renderPassInfo: vk.RenderPassBeginInfo 
    renderPassInfo.sType = .RENDER_PASS_BEGIN_INFO
    renderPassInfo.renderPass = ctx.sc.renderPass
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

    for m in ctx.render.modules {
        for i in 0..<len(m.renderProcedures) {
            m.renderProcedures[i]->record(ctx, buffer, ctx.currentFrame)
        }
    }

  
    vk.CmdEndRenderPass(buffer)
    if vk.EndCommandBuffer(buffer) != .SUCCESS {
        fmt.eprintln("failed to end command buffer")
    }
}



copyBufferToImage :: proc(ctx: ^Context, buffer: vk.Buffer, w,h : u32, texture: ^Texture) {
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