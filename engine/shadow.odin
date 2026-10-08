package engine

import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:mem"
import vk "vendor:vulkan"

ShadowContext :: struct {
	w, h:                u32,
	shadowMap:           DepthImage,
	ubo:                 ShadowUBO,
	descriptorSetLayout: vk.DescriptorSetLayout,
	descriptorSets:      []vk.DescriptorSet,
	// Specify a vk.Format upfront
}

ShadowUBO :: struct {
	lightViewProjection: Mat4,
}

SHADOW_VERTEX_ATTRIBUTES := [?]vk.VertexInputAttributeDescription {
	{
		binding = 0,
		location = 0,
		format = .R32G32B32_SFLOAT,
		offset = cast(u32)offset_of(Vertex, pos),
	},
}

recordShadowPass :: proc(
	module: ^ThreeDModule,
	ctx: ^Context,
	cmd: vk.CommandBuffer,
	frameIndex: u32,
) {
	shadowMap := &ctx.shadow.shadowMap

	depthAttachment := vk.RenderingAttachmentInfo {
		sType = .RENDERING_ATTACHMENT_INFO,
		imageView = shadowMap.view,
		imageLayout = .DEPTH_ATTACHMENT_OPTIMAL,
		loadOp = .CLEAR,
		storeOp = .STORE,
		clearValue = vk.ClearValue {
			depthStencil = vk.ClearDepthStencilValue{depth = 1.0, stencil = 0},
		},
	}

	renderingInfo := vk.RenderingInfo {
		sType = .RENDERING_INFO,
		renderArea = vk.Rect2D {
			offset = vk.Offset2D{x = 0, y = 0},
			extent = vk.Extent2D {
				width = ctx.sc.swapchain.extent.width,
				height = ctx.sc.swapchain.extent.height,
			},
		},
		layerCount = 1,
		colorAttachmentCount = 0,
		pColorAttachments = nil,
		pDepthAttachment = &depthAttachment,
	}

	vk.CmdBeginRendering(cmd, &renderingInfo)

	vk.CmdBindPipeline(cmd, .GRAPHICS, module.pipeline.pipelines["shadow"])

	vk.CmdBindDescriptorSets(
		cmd,
		.GRAPHICS,
		module.pipeline.shadowPipelineLayout,
		0,
		1,
		&ctx.shadow.descriptorSets[frameIndex],
		0,
		nil,
	)

	vk.CmdSetViewport(
		cmd,
		0,
		1,
		&vk.Viewport {
			x = 0,
			y = 0,
			width = f32(ctx.sc.swapchain.extent.width),
			height = f32(ctx.sc.swapchain.extent.height),
			minDepth = 0,
			maxDepth = 1,
		},
	)

	vk.CmdSetScissor(
		cmd,
		0,
		1,
		&vk.Rect2D {
			offset = vk.Offset2D{x = 0, y = 0},
			extent = vk.Extent2D {
				width = ctx.sc.swapchain.extent.width,
				height = ctx.sc.swapchain.extent.height,
			},
		},
	)

	for &o in module.meshes {
		mesh := ctx.resource.meshes[o.meshIndex]

		vertexBuffers := [?]vk.Buffer{mesh.vertexBuffer.buffer}

		offsets := [?]vk.DeviceSize{0}

		vk.CmdBindVertexBuffers(cmd, 0, 1, &vertexBuffers[0], &offsets[0])

		vk.CmdBindIndexBuffer(cmd, mesh.indexBuffer.buffer, 0, .UINT32)

		vk.CmdPushConstants(
			cmd,
			module.pipeline.shadowPipelineLayout,
			{.VERTEX},
			0,
			size_of(Mat4),
			&o.worldTransform,
		)

		for primitive in mesh.primitives {
			vk.CmdDrawIndexed(
				cmd,
				cast(u32)primitive.indexCount,
				1,
				cast(u32)primitive.firstIndex,
				primitive.firstVertex,
				0,
			)
		}
	}

	vk.CmdEndRendering(cmd)
}

transitionShadowMapForSampling :: proc(ctx: ^Context, cmd: vk.CommandBuffer) {
	shadowMap := &ctx.shadow.shadowMap

	barrier := vk.ImageMemoryBarrier {
		sType = .IMAGE_MEMORY_BARRIER,
		srcAccessMask = {.DEPTH_STENCIL_ATTACHMENT_WRITE},
		dstAccessMask = {.SHADER_READ},
		oldLayout = .DEPTH_STENCIL_ATTACHMENT_OPTIMAL,
		newLayout = .SHADER_READ_ONLY_OPTIMAL,
		srcQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
		dstQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
		image = shadowMap.image.texture,
		subresourceRange = vk.ImageSubresourceRange {
			aspectMask = {.DEPTH},
			baseMipLevel = 0,
			levelCount = 1,
			baseArrayLayer = 0,
			layerCount = 1,
		},
	}

	vk.CmdPipelineBarrier(
		cmd,
		{.LATE_FRAGMENT_TESTS},
		{.FRAGMENT_SHADER},
		{},
		0,
		nil,
		0,
		nil,
		1,
		&barrier,
	)
}

transitionShadowMapForRendering :: proc(ctx: ^Context, cmd: vk.CommandBuffer) {
	shadowMap := &ctx.shadow.shadowMap

	barrier := vk.ImageMemoryBarrier {
		sType = .IMAGE_MEMORY_BARRIER,
		srcAccessMask = {},
		dstAccessMask = {.DEPTH_STENCIL_ATTACHMENT_WRITE},
		oldLayout = .UNDEFINED,
		newLayout = .DEPTH_STENCIL_ATTACHMENT_OPTIMAL,
		srcQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
		dstQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
		image = shadowMap.image.texture,
		subresourceRange = vk.ImageSubresourceRange {
			aspectMask = {.DEPTH},
			baseMipLevel = 0,
			levelCount = 1,
			baseArrayLayer = 0,
			layerCount = 1,
		},
	}

	vk.CmdPipelineBarrier(
		cmd,
		{.TOP_OF_PIPE},
		{.EARLY_FRAGMENT_TESTS, .LATE_FRAGMENT_TESTS},
		{},
		0,
		nil,
		0,
		nil,
		1,
		&barrier,
	)
}
