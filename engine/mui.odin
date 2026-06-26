package engine

import mu "vendor:microui"
import sdl "vendor:sdl2"
import vk "vendor:vulkan"

import "core:fmt"
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
	for &buf in ctx.ui.vertexBuffers {
		destroyBuffer("uiVertex", ctx.vulkan.device, buf)
	}
	clear(&ctx.ui.vertexBuffers)
}

RenderUI :: proc(cmdBuf: vk.CommandBuffer, ctx: ^Context, element: ^UIElement, frame: u32) {
	if element == nil do return

	swapchain := ctx.sc.swapchain


	fmt.printf("Rendering UI text: '%s'\n", element.stagedText)
	fmt.printf("%v", element)
	vertices := render(ctx, element^)
	fmt.printf("Generated %d vertices for UI text\n", len(vertices))
	defer delete(vertices)

	if len(vertices) > 0 {
		vertex_buffer := createVertexBuffer(ctx, vertices[:])
		if vertex_buffer != nil {
			fmt.printf("UI vertex buffer created with %d vertices\n", len(vertices))
			append(&ctx.ui.vertexBuffers, vertex_buffer^)
			screen_size := Vec2{f32(swapchain.extent.width), f32(swapchain.extent.height)}
			vk.CmdPushConstants(
				cmdBuf,
				ctx.pipe.uiPipelineLayout,
				{.VERTEX, .FRAGMENT},
				0,
				size_of(Vec2),
				&screen_size,
			)

			vertexBuffers := [?]vk.Buffer{vertex_buffer.buffer}
			offsets := [?]vk.DeviceSize{0}
			vk.CmdBindVertexBuffers(cmdBuf, 0, 1, raw_data(vertexBuffers[:]), raw_data(offsets[:]))
			vk.CmdDraw(cmdBuf, u32(vertex_buffer.length), 1, 0, 0)
		} else {
			fmt.printf("Failed to create UI vertex buffer\n")
		}
	} else {
		fmt.printf("No vertices generated for UI text\n")
	}


	children := element.children
	for &child in children {
		if child != nil do RenderUI(cmdBuf, ctx, child, frame)
	}

}

AddUI :: proc(ctx: ^Context) -> bool {
	font, font_ok := createFontFromFile(ctx, "Roboto-Regular", 32.0, "arial")
	ctx.ui.font = font

	if !font_ok {
		fmt.eprintln("Failed to load font")
		return false
	}
	text := ctx.scene.isPlayer ? "Playiiing" : "Viewing"

	viewport := addViewport(ctx, nil)

	text1 := addText(ctx, viewport, text, 2, DefaultStyle)
	text2 := addText(ctx, viewport, text, 2, DefaultStyle)
	btn1 := addButton(ctx, viewport, "I am a button", 3, DefaultButtonStyle, Vec2{0, 0})

	ctx.ui.root = viewport
	append(&viewport.children, text1, text2, btn1)

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
