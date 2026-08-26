package engine

import mu "vendor:microui"
import sdl "vendor:sdl2"
import vk "vendor:vulkan"

import "core:fmt"
import "core:mem"
import "core:strings"
import "vendor:sdl2/ttf"

import "core:math"
import "core:math/linalg"


UpdateUI :: proc(ctx: ^Context, element: ^UIElement) {
	if element == nil do return

	element.text = element.stagedText

	children := element.children
	for &child in children {
		if child != nil do UpdateUI(ctx, child)
	}

}

ClearUI :: proc(cmdBuf: vk.CommandBuffer, ctx: ^Context, element: ^UIElement) {
	if element == nil do return

	children := element.children
	for &child in children {
		if child != nil do ClearUI(cmdBuf, ctx, child)
	}
}

freeUIVertexBuffers :: proc(ctx: ^Context) {
	for &buffer in ctx.ui.vertexBuffers {
		destroyBuffer("ui", ctx.vulkan.device, buffer)
	}
}

BuildUIVertices :: proc(ctx: ^Context, element: ^UIElement, vertices: ^[dynamic]TextVertex) {
	if element == nil do return

	append(vertices, ..render(ctx, element)[:])
	for child in element.children {
		BuildUIVertices(ctx, child, vertices)
	}


}

RenderUI :: proc(cmdBuf: vk.CommandBuffer, ctx: ^Context, frame: u32) {
	clear(&ctx.ui.vertices)

	BuildUIVertices(ctx, ctx.ui.root, &ctx.ui.vertices)

	if len(ctx.ui.vertices) == 0 {
		return
	}

	buffer := &ctx.ui.vertexBuffers[frame]
	buffer.length = len(ctx.ui.vertices)

	mem.copy(
		buffer.mapped_ptr,
		raw_data(ctx.ui.vertices),
		len(ctx.ui.vertices) * size_of(TextVertex),
	)

	screen_size := Vec2{f32(ctx.sc.swapchain.extent.width), f32(ctx.sc.swapchain.extent.height)}

	vk.CmdPushConstants(
		cmdBuf,
		ctx.pipe.compositePipelineLayout,
		{.VERTEX, .FRAGMENT},
		0,
		size_of(Vec2),
		&screen_size,
	)

	vertexBuffers := [?]vk.Buffer{buffer.buffer}
	offsets := [?]vk.DeviceSize{0}

	vk.CmdBindVertexBuffers(cmdBuf, 0, 1, raw_data(vertexBuffers[:]), raw_data(offsets[:]))

	vk.CmdDraw(cmdBuf, u32(buffer.length), 1, 0, 0)
}

createUIVertexBuffers :: proc(ctx: ^Context) {

	maxVertices := 10000
	bufferSize := vk.DeviceSize(maxVertices * size_of(TextVertex))

	for i in 0 ..< MAX_FRAMES_IN_FLIGHT {

		createBuffer(
			ctx,
			bufferSize,
			{.VERTEX_BUFFER},
			{.HOST_VISIBLE, .HOST_COHERENT},
			&ctx.ui.vertexBuffers[i],
			"ui vertex buffer",
		)

		ptr: rawptr
		vk.MapMemory(ctx.vulkan.device, ctx.ui.vertexBuffers[i].memory, 0, bufferSize, {}, &ptr)

		ctx.ui.vertexBuffers[i].mapped_ptr = ptr
	}
}

AddUI :: proc(ctx: ^Context) -> bool {
	font, ok := createFontFromFile(ctx, "Roboto-Regular", 32.0, "arial")
	if !ok {
		return false
	}

	ctx.ui.font = font

	root := addViewport(
		ctx,
		nil,
		.Normal,
		Pixels{cast(f32)ctx.sc.swapchain.extent.width},
		Pixels{cast(f32)ctx.sc.swapchain.extent.height},
	)

	root.rect = Rect {
		min = {0, 0},
		max = {cast(f32)ctx.sc.swapchain.extent.width, cast(f32)ctx.sc.swapchain.extent.height},
	}
	root.layout = .Horizontal


	ctx.ui.root = root


	gameViewport := addViewport(ctx, root, .Render, .Grow, Percent{50})

	firstWindow := addViewport(ctx, root, .Normal, .Grow, Percent{50})
	firstWindow.layout = .Vertical
	firstWindow.style.color = Vec4{0.1, 255, 255, 0.1}

	debug := addViewport(ctx, firstWindow, .Debug, .Grow, Percent{50})
	debug.style.color = Vec4{0.1, 0.1, 255, 0.1}
	addText(ctx, firstWindow, "Playing", DefaultStyle)
	addText(ctx, firstWindow, "Hello", DefaultStyle)
	addButton(ctx, firstWindow, "Button", DefaultButtonStyle)

	return true
}

UI_VERTEX_BINDING := vk.VertexInputBindingDescription {
	binding   = 0,
	stride    = size_of(TextVertex),
	inputRate = .VERTEX,
}

UI_VERTEX_ATTRIBUTES := [3]vk.VertexInputAttributeDescription {
	{
		binding = 0,
		location = 0,
		format = .R32G32_SFLOAT,
		offset = cast(u32)offset_of(TextVertex, pos),
	},
	{
		binding = 0,
		location = 1,
		format = .R32G32_SFLOAT,
		offset = cast(u32)offset_of(TextVertex, tex_coord),
	},
	{
		binding = 0,
		location = 2,
		format = .R32G32B32A32_SFLOAT,
		offset = cast(u32)offset_of(TextVertex, color),
	},
}
