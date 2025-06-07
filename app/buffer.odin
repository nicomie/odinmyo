package app

import vk "vendor:vulkan"

import "core:time"
import "core:math"
import "core:math/linalg"
import "core:os"
import "core:fmt"
import "core:mem"





Buffer :: struct
{
	buffer: vk.Buffer,
	memory: vk.DeviceMemory,
	length: int,
	size:   vk.DeviceSize,
}

UniformBuffers :: struct {
    buffers: []Buffer,
    buffersMapped: []rawptr
}

create_staged_buffer :: proc(
    using r: ^Renderer,
    dst_buffer: ^Buffer,
    data: rawptr,
    size: vk.DeviceSize,
    usage: vk.BufferUsageFlags
) {
    staging: Buffer
    create_buffer(r, size, {.TRANSFER_SRC}, {.HOST_VISIBLE, .HOST_COHERENT}, &staging, data)
    create_buffer(r, size, usage, {.DEVICE_LOCAL}, dst_buffer)
    copy_buffer(r, staging, dst_buffer^, size)

    vk.DestroyBuffer(device, staging.buffer, nil)
    vk.FreeMemory(device, staging.memory, nil)
}

copy_buffer :: proc(using r: ^Renderer, src, dst: Buffer, size: vk.DeviceSize) {
          
    cmdBuffer, res := begin_command(r)
    if res != .SUCCESS {
        fmt.eprintln("failed copy buffer")
    }
          
    defer end_command(r, &cmdBuffer)
    copyRegion := vk.BufferCopy{
        srcOffset = 0,
        dstOffset = 0,
        size = size,
    }

    vk.CmdCopyBuffer(cmdBuffer, src.buffer, dst.buffer, 1, &copyRegion)
}

create_buffer :: proc(
    using r: ^Renderer, 
    bufferSize: vk.DeviceSize, 
    usage: vk.BufferUsageFlags, 
    properties: vk.MemoryPropertyFlags, 
    buffer: ^Buffer,
    data: rawptr = nil
)  {
    
    bufferInfo := vk.BufferCreateInfo{
        sType = .BUFFER_CREATE_INFO,
        size = bufferSize,
        usage = usage,
        sharingMode = .EXCLUSIVE,
    }
    check_vk(vk.CreateBuffer(device, &bufferInfo, nil, &buffer.buffer))

    memRequirements: vk.MemoryRequirements
    vk.GetBufferMemoryRequirements(device, buffer.buffer, &memRequirements)

    allocInfo := vk.MemoryAllocateInfo{
        sType = .MEMORY_ALLOCATE_INFO,
        allocationSize = memRequirements.size,
        memoryTypeIndex = find_mem_type(physicalDevice, memRequirements.memoryTypeBits, properties)
    }

    check_vk(vk.AllocateMemory(device, &allocInfo, nil, &buffer.memory))
    check_vk(vk.BindBufferMemory(device, buffer.buffer, buffer.memory, 0))

    if data != nil {
        ptr: rawptr
        check_vk(vk.MapMemory(device, buffer.memory, 0, bufferSize, {}, &ptr))
        mem.copy(ptr, data, int(bufferSize))
        vk.UnmapMemory(device, buffer.memory)
    }

}

find_mem_type :: proc(physicalDevice: vk.PhysicalDevice, typeFilter: u32, props: vk.MemoryPropertyFlags) -> u32{
    memProps : vk.PhysicalDeviceMemoryProperties
    vk.GetPhysicalDeviceMemoryProperties(physicalDevice, &memProps)

    for i in 0..<memProps.memoryTypeCount {
        if ((typeFilter & (1 << i) != 0) && (memProps.memoryTypes[i].propertyFlags & props) == props) {
            return i
        }
    }

    fmt.eprintln("failed to find suitable memory type")
    os.exit(1)
}

destroy_buffer :: proc(r: ^Renderer, buffer: Buffer) {
    // Implementation...
}

copy_buffer_to_image :: proc(using r: ^Renderer, image: ^Image, buffer: vk.Buffer, w,h : u32) {
    cmdBuffer, err := begin_command(r)
    defer end_command(r, &cmdBuffer)

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

    vk.CmdCopyBufferToImage(cmdBuffer, buffer, image.texture, .TRANSFER_DST_OPTIMAL, 1, &region)
}

record_command_buffer :: proc(using r: ^Renderer, buffer: vk.CommandBuffer, imageIndex: u32) {
    beginInfo: vk.CommandBufferBeginInfo
    beginInfo.sType = .COMMAND_BUFFER_BEGIN_INFO
    beginInfo.pInheritanceInfo = nil

    check_vk(vk.BeginCommandBuffer(buffer, &beginInfo))

    renderPassInfo: vk.RenderPassBeginInfo 
    renderPassInfo.sType = .RENDER_PASS_BEGIN_INFO
    renderPassInfo.renderPass = render_pass.render_pass
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

    vk.CmdBindPipeline(buffer, .GRAPHICS, render_pass.pipeline.handle)
    for mesh in meshes {
        vertexBuffers := [?]vk.Buffer{mesh.vertex_buffer.buffer}
        offsets := [?]vk.DeviceSize{0}
        vk.CmdBindVertexBuffers(buffer, 0, 1, &vertexBuffers[0], &offsets[0])
        vk.CmdBindIndexBuffer(buffer, mesh.index_buffer.buffer, 0, .UINT16)
        vk.CmdBindDescriptorSets(buffer, .GRAPHICS, render_pass.pipeline.layout, 0, 1, &descriptor_sets[currentFrame], 0, nil)
       vk.CmdDrawIndexed(buffer, cast(u32)mesh.index_buffer.length, 1, 0, 0, 0)
    }

    vk.CmdEndRenderPass(buffer)

    check_vk(vk.EndCommandBuffer(buffer))
}

create_uniform_buffers :: proc(using r: ^Renderer) -> UniformBuffers {
    uniformBuffers: UniformBuffers

    bufferSize := cast(vk.DeviceSize)size_of(UBO)

    uniformBuffers.buffers = make([]Buffer, MAX_FRAMES_IN_FLIGHT)
    uniformBuffers.buffersMapped = make([]rawptr, MAX_FRAMES_IN_FLIGHT)

    for i in 0..<MAX_FRAMES_IN_FLIGHT {
        create_buffer(r, bufferSize, {.UNIFORM_BUFFER}, {.HOST_VISIBLE, .HOST_COHERENT}, &uniformBuffers.buffers[i])
        vk.MapMemory(device, uniformBuffers.buffers[i].memory, 0, bufferSize, {}, &uniformBuffers.buffersMapped[i])
    }
    return uniformBuffers
}

create_framebuffer :: proc(using r: ^Renderer) {
    swapchain.framebuffers = make([]vk.Framebuffer, len(swapchain.imageViews))

    for i in 0..<len(swapchain.imageViews) {
        attachments := []vk.ImageView{swapchain.imageViews[i], depthImage.view }
 
        framebufferInfo: vk.FramebufferCreateInfo
        framebufferInfo.sType = .FRAMEBUFFER_CREATE_INFO
        framebufferInfo.renderPass = render_pass.render_pass
        framebufferInfo.attachmentCount = cast(u32)len(attachments)
        framebufferInfo.pAttachments = &attachments[0]
        framebufferInfo.width = swapchain.extent.width
        framebufferInfo.height = swapchain.extent.height
        framebufferInfo.layers = 1


        if vk.CreateFramebuffer(device, &framebufferInfo, nil, &swapchain.framebuffers[i]) != .SUCCESS{
            fmt.eprintf("Failed to create fram buffer for index %d \n", i)
            os.exit(1)
        }
    }
}

create_command_buffers :: proc(r: ^Renderer) {
    allocInfo: vk.CommandBufferAllocateInfo
    allocInfo.sType = .COMMAND_BUFFER_ALLOCATE_INFO
    allocInfo.commandPool = r.commandPool 
    allocInfo.level = .PRIMARY
    allocInfo.commandBufferCount = MAX_FRAMES_IN_FLIGHT

    if vk.AllocateCommandBuffers(r.device, &allocInfo, &r.commandBuffers[0]) != .SUCCESS {
        fmt.eprintln("failed to create command buffer")
        os.exit(1)
    }
}
