package engine

import "core:c"
import "core:encoding/base32"
import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:mem"
import "core:os"
import vk "vendor:vulkan"


Buffer :: struct {
	buffer:     vk.Buffer,
	memory:     vk.DeviceMemory,
	length:     int,
	size:       vk.DeviceSize,
	mapped_ptr: rawptr,
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
	buffer.size = bufferSize
	device := ctx.vulkan.device

	bufferInfo := vk.BufferCreateInfo {
		sType       = .BUFFER_CREATE_INFO,
		size        = bufferSize,
		usage       = usage,
		sharingMode = .EXCLUSIVE,
	}
	checkVk(vk.CreateBuffer(device, &bufferInfo, nil, &buffer.buffer))

	memRequirements: vk.MemoryRequirements
	vk.GetBufferMemoryRequirements(device, buffer.buffer, &memRequirements)

	allocInfo := vk.MemoryAllocateInfo {
		sType           = .MEMORY_ALLOCATE_INFO,
		allocationSize  = memRequirements.size,
		memoryTypeIndex = findMemType(
			ctx.vulkan.physicalDevice,
			memRequirements.memoryTypeBits,
			properties,
		),
	}

	checkVk(vk.AllocateMemory(device, &allocInfo, nil, &buffer.memory))
	checkVk(vk.BindBufferMemory(device, buffer.buffer, buffer.memory, 0))

	if data != nil {
		ptr: rawptr
		checkVk(vk.MapMemory(device, buffer.memory, 0, bufferSize, {}, &ptr))
		mem.copy(ptr, data, int(bufferSize))
		vk.UnmapMemory(device, buffer.memory)
	}

	when DEBUG {
		fmt.printf("Created buffer %s: %p\n", name, buffer.buffer)
	}
}

copyBuffer :: proc(ctx: ^Context, src, dst: Buffer, size: vk.DeviceSize) {
	cmdBuffer := beginCommand(ctx)
	defer endCommand(ctx, &cmdBuffer)
	copyRegion := vk.BufferCopy {
		srcOffset = 0,
		dstOffset = 0,
		size      = size,
	}
	vk.CmdCopyBuffer(cmdBuffer, src.buffer, dst.buffer, 1, &copyRegion)
}

createUIBuffers :: proc(ctx: ^Context) {

	maxVertices := 10000
	size := vk.DeviceSize(maxVertices * size_of(TextVertex))

	for i in 0 ..< MAX_FRAMES_IN_FLIGHT {

		createBuffer(
			ctx,
			size,
			{.VERTEX_BUFFER},
			{.HOST_VISIBLE, .HOST_COHERENT},
			&ctx.ui.vertexBuffers[i],
			"ui buffer",
		)
	}
}

createVertexBuffer :: proc(ctx: ^Context, vertices: []$T) -> ^Buffer {
	buffer := new(Buffer)
	buffer.length = len(vertices)
	buffer.size = cast(vk.DeviceSize)(len(vertices) * size_of(T))

	if buffer.size == 0 {
		return nil
	}

	staging: Buffer
	createBuffer(
		ctx,
		buffer.size,
		{.TRANSFER_SRC},
		{.HOST_VISIBLE, .HOST_COHERENT},
		&staging,
		"vStaging",
		raw_data(vertices),
	)

	createBuffer(
		ctx,
		buffer.size,
		{.VERTEX_BUFFER, .TRANSFER_DST},
		{.DEVICE_LOCAL},
		buffer,
		"vBuffer",
	)
	copyBuffer(ctx, staging, buffer^, buffer.size)

	destroyBuffer("vStaging", ctx.vulkan.device, staging)
	return buffer
}

createIndexBuffer :: proc(ctx: ^Context, indices: []u32) -> ^Buffer {
	device := ctx.vulkan.device

	buffer := new(Buffer)
	buffer.length = len(indices)
	buffer.size = cast(vk.DeviceSize)(len(indices) * size_of(indices[0]))

	staging: Buffer
	createBuffer(
		ctx,
		buffer.size,
		{.TRANSFER_SRC},
		{.HOST_VISIBLE, .HOST_COHERENT},
		&staging,
		"indexStaging",
	)

	data: rawptr
	vk.MapMemory(ctx.vulkan.device, staging.memory, 0, buffer.size, {}, &data)
	mem.copy(data, raw_data(indices), cast(int)buffer.size)
	vk.UnmapMemory(device, staging.memory)

	createBuffer(
		ctx,
		buffer.size,
		{.TRANSFER_DST, .INDEX_BUFFER},
		{.DEVICE_LOCAL},
		buffer,
		"iBuffer",
	)
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

	for i in 0 ..< MAX_FRAMES_IN_FLIGHT {
		if vk.AllocateCommandBuffers(device, &allocInfo, &ctx.frames[i].commandBuffer) !=
		   .SUCCESS {
			fmt.eprintln("failed to create command buffer")
			os.exit(1)
		}
	}
}

destroyBuffer :: proc(name: string, device: vk.Device, buf: Buffer) {
	when DEBUG {
		fmt.printf("Destroying buffer %s: %p\n", name, buf.buffer)
	}
	vk.DestroyBuffer(device, buf.buffer, nil)
	vk.FreeMemory(device, buf.memory, nil)
}

recordCommandBuffer :: proc(ctx: ^Context, buffer: vk.CommandBuffer, imageIndex: u32) {
	swapchain := &ctx.sc.swapchain
	beginInfo := vk.CommandBufferBeginInfo {
		sType = .COMMAND_BUFFER_BEGIN_INFO,
	}
	checkVk(vk.BeginCommandBuffer(buffer, &beginInfo))

	clearValue := vk.ClearValue {
		color = {float32 = [4]f32{0, 0, 0, 1}},
	}
	if !ctx.sc.sceneColorInitialized {
		cmdTransitionImageLayout(
			buffer,
			ctx.sc.sceneColor.image.texture,
			.UNDEFINED,
			.COLOR_ATTACHMENT_OPTIMAL,
			{.TOP_OF_PIPE},
			{.COLOR_ATTACHMENT_OUTPUT},
			{},
			{.COLOR_ATTACHMENT_WRITE},
			{.COLOR},
		)
		cmdTransitionImageLayout(
			buffer,
			ctx.sc.sceneDepth.image.texture,
			.UNDEFINED,
			.DEPTH_STENCIL_ATTACHMENT_OPTIMAL,
			{.TOP_OF_PIPE},
			{.EARLY_FRAGMENT_TESTS},
			{},
			{.DEPTH_STENCIL_ATTACHMENT_WRITE},
			{.DEPTH},
		)
	} else {
		cmdTransitionImageLayout(
			buffer,
			ctx.sc.sceneColor.image.texture,
			.SHADER_READ_ONLY_OPTIMAL,
			.COLOR_ATTACHMENT_OPTIMAL,
			{.FRAGMENT_SHADER},
			{.COLOR_ATTACHMENT_OUTPUT},
			{.SHADER_READ},
			{.COLOR_ATTACHMENT_WRITE},
			{.COLOR},
		)
	}
	depthAttachment := vk.RenderingAttachmentInfo {
		sType = .RENDERING_ATTACHMENT_INFO,
		imageView = ctx.sc.sceneDepth.view,
		imageLayout = .DEPTH_STENCIL_ATTACHMENT_OPTIMAL,
		loadOp = .CLEAR,
		storeOp = .DONT_CARE,
		clearValue = vk.ClearValue{depthStencil = {1.0, 0}},
	}
	sceneAttachment := vk.RenderingAttachmentInfo {
		sType       = .RENDERING_ATTACHMENT_INFO,
		imageView   = ctx.sc.sceneColor.view,
		imageLayout = .COLOR_ATTACHMENT_OPTIMAL,
		loadOp      = .CLEAR,
		storeOp     = .STORE,
		clearValue  = clearValue,
	}
	renderingInfo := vk.RenderingInfo {
		sType = .RENDERING_INFO,
		renderArea = {offset = {0, 0}, extent = swapchain.extent},
		layerCount = 1,
		colorAttachmentCount = 1,
		pColorAttachments = &sceneAttachment,
		pDepthAttachment = &depthAttachment,
	}

	vk.CmdBeginRenderingKHR(buffer, &renderingInfo)
	for m in ctx.render.modules {
		for i in 0 ..< len(m.renderProcedures) {
			if m.renderProcedures[i].pass != .Scene do continue
			viewport, scissor := getViewportAndScissor(
				ctx,
				m.renderProcedures[i].region,
				swapchain,
			)
			vk.CmdSetViewport(buffer, 0, 1, &viewport)
			vk.CmdSetScissor(buffer, 0, 1, &scissor)
			m.renderProcedures[i]->record(ctx, buffer, ctx.currentFrame)
		}
	}
	vk.CmdEndRenderingKHR(buffer)
	ctx.sc.sceneColorInitialized = true

	cmdTransitionImageLayout(
		buffer,
		ctx.sc.sceneColor.image.texture,
		.COLOR_ATTACHMENT_OPTIMAL,
		.SHADER_READ_ONLY_OPTIMAL,
		{.COLOR_ATTACHMENT_OUTPUT},
		{.FRAGMENT_SHADER},
		{.COLOR_ATTACHMENT_WRITE},
		{.SHADER_READ},
		{.COLOR},
	)
	if ctx.swapchainImageInitialized[imageIndex] {
		cmdTransitionImageLayout(
			buffer,
			swapchain.images[imageIndex],
			.PRESENT_SRC_KHR,
			.COLOR_ATTACHMENT_OPTIMAL,
			{.COLOR_ATTACHMENT_OUTPUT},
			{.COLOR_ATTACHMENT_OUTPUT},
			{.MEMORY_READ},
			{.COLOR_ATTACHMENT_WRITE},
			{.COLOR},
		)
	} else {
		cmdTransitionImageLayout(
			buffer,
			swapchain.images[imageIndex],
			.UNDEFINED,
			.COLOR_ATTACHMENT_OPTIMAL,
			{.TOP_OF_PIPE},
			{.COLOR_ATTACHMENT_OUTPUT},
			{},
			{.COLOR_ATTACHMENT_WRITE},
			{.COLOR},
		)
	}

	swapchainAttachment := vk.RenderingAttachmentInfo {
		sType       = .RENDERING_ATTACHMENT_INFO,
		imageView   = swapchain.attachments.views[imageIndex],
		imageLayout = .COLOR_ATTACHMENT_OPTIMAL,
		loadOp      = .CLEAR,
		storeOp     = .STORE,
		clearValue  = clearValue,
	}
	renderingInfo.pColorAttachments = &swapchainAttachment
	renderingInfo.pDepthAttachment = nil
	vk.CmdBeginRenderingKHR(buffer, &renderingInfo)
	for m in ctx.render.modules {
		for i in 0 ..< len(m.renderProcedures) {
			if m.renderProcedures[i].pass == .Scene do continue
			viewport, scissor := getViewportAndScissor(
				ctx,
				m.renderProcedures[i].region,
				swapchain,
			)
			vk.CmdSetViewport(buffer, 0, 1, &viewport)
			vk.CmdSetScissor(buffer, 0, 1, &scissor)
			m.renderProcedures[i]->record(ctx, buffer, ctx.currentFrame)
		}
	}
	vk.CmdEndRenderingKHR(buffer)
	ctx.swapchainImageInitialized[imageIndex] = true
	cmdTransitionImageLayout(
		buffer,
		swapchain.images[imageIndex],
		.COLOR_ATTACHMENT_OPTIMAL,
		.PRESENT_SRC_KHR,
		{.COLOR_ATTACHMENT_OUTPUT},
		{.BOTTOM_OF_PIPE},
		{.COLOR_ATTACHMENT_WRITE},
		{.MEMORY_READ},
		{.COLOR},
	)

	checkVk(vk.EndCommandBuffer(buffer))
}

cmdTransitionImageLayout :: proc(
	buffer: vk.CommandBuffer,
	image: vk.Image,
	oldLayout, newLayout: vk.ImageLayout,
	sourceStage, destinationStage: vk.PipelineStageFlags,
	sourceAccess, destinationAccess: vk.AccessFlags,
	aspectMask: vk.ImageAspectFlags,
) {
	barrier := vk.ImageMemoryBarrier {
		sType = .IMAGE_MEMORY_BARRIER,
		oldLayout = oldLayout,
		newLayout = newLayout,
		srcAccessMask = sourceAccess,
		dstAccessMask = destinationAccess,
		image = image,
		subresourceRange = {
			aspectMask = aspectMask,
			baseMipLevel = 0,
			levelCount = 1,
			baseArrayLayer = 0,
			layerCount = 1,
		},
	}
	vk.CmdPipelineBarrier(buffer, sourceStage, destinationStage, {}, 0, nil, 0, nil, 1, &barrier)
}

getViewportAndScissor :: proc(
	ctx: ^Context,
	region: RenderRegion,
	swapchain: ^Swapchain,
) -> (
	vk.Viewport,
	vk.Rect2D,
) {
	viewport: vk.Viewport
	scissor: vk.Rect2D


	#partial switch t in region {
	case RenderOption:
		{
			viewport.x = 0.0
			viewport.y = 0.0
			viewport.width = cast(f32)swapchain.extent.width
			viewport.height = cast(f32)swapchain.extent.height
			viewport.minDepth = 0.0
			viewport.maxDepth = 1.0

			scissor.offset = {0, 0}
			scissor.extent = swapchain.extent
		}
	case ^UIElement:
		{
			gameViewport := findWindow(ctx, ctx.ui.root, .Render)
			minmax := gameViewport.rect

			viewport.x = minmax.min.x
			viewport.y = minmax.min.y
			viewport.width = minmax.max.x - minmax.min.x
			viewport.height = minmax.max.y - minmax.min.y
			viewport.minDepth = 0.0
			viewport.maxDepth = 1.0

			scissor.offset = {cast(i32)minmax.min.x, cast(i32)minmax.min.y}

			scissor.extent = {
				cast(u32)(minmax.max.x - minmax.min.x),
				cast(u32)(minmax.max.y - minmax.min.y),
			}
		}
	}

	return viewport, scissor
}

copyBufferToImage :: proc(ctx: ^Context, buffer: vk.Buffer, w, h: u32, texture: ^Texture) {
	cmdBuffer := beginCommand(ctx)
	defer endCommand(ctx, &cmdBuffer)

	region: vk.BufferImageCopy
	region.bufferOffset = 0
	region.bufferRowLength = 0
	region.bufferImageHeight = 0
	region.imageSubresource.aspectMask = {.COLOR}
	region.imageSubresource.mipLevel = 0
	region.imageSubresource.baseArrayLayer = 0
	region.imageSubresource.layerCount = 1
	region.imageOffset = {0, 0, 0}
	region.imageExtent = {w, h, 1}

	vk.CmdCopyBufferToImage(
		cmdBuffer,
		buffer,
		texture.handle.texture,
		.TRANSFER_DST_OPTIMAL,
		1,
		&region,
	)
}
