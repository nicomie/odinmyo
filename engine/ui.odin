package engine

import vk "vendor:vulkan"

DefaultStyle :: UIStyle {
	color            = Vec4{255, 1, 1, 1},
	border_radius    = 1.0,
	border_thickness = 1.0,
	font_size        = 12.0,
}

DefaultButtonStyle :: UIStyle {
	color            = Vec4{1, 255, 1, 1},
	border_radius    = 1.0,
	border_thickness = 1.0,
	font_size        = 22.0,
}

Rect :: struct {
	min: Vec2,
	max: Vec2,
}

UIContext :: struct {
	font:             Font,
	root:             ^UIElement,
	id:               i32,
	uiDescriptorSets: [2 * MAX_FRAMES_IN_FLIGHT]vk.DescriptorSet,
	vertexBuffers:    [dynamic]Buffer,
}

UIStyle :: struct {
	color:            Vec4,
	border_radius:    f32,
	border_thickness: f32,
	font_size:        f32,
}

UIElement :: struct {
	id:              u32,
	kind:            UIKind,
	rect:            Rect,
	offset:          Vec2,
	pos:             Vec2,
	hovered:         bool,
	pressed:         bool,
	focused:         bool,
	parent:          ^UIElement,
	children:        [dynamic]^UIElement,
	style:           UIStyle,
	viewportContext: ViewportContext,
	text:            string,
	stagedText:      string,
}

ViewportContext :: struct {
	startX: f32,
	startY: f32,
}

UICommand :: struct {
	kind:            UIKind,
	rect:            Rect,
	color:           Vec4,
	zIndex:          i32,
	borderRadius:    f32,
	borderThickness: f32,
	text:            string,
}

UIKind :: enum {
	Rect,
	Button,
	Image,
	Text,
	Viewport,
	ClipBegin,
	ClipEnd,
}

addButton :: proc(
	ctx: ^Context,
	parent: ^UIElement,
	text: string,
	zIndex: i32,
	style: UIStyle,
	offset: Vec2,
) -> ^UIElement {

	id := ctx.ui.id
	ctx.ui.id += 1

	button := new(UIElement)
	button.kind = .Button
	button.text = text
	button.stagedText = text
	button.style = style

	padding_x: f32 = 8.0
	padding_y: f32 = 4.0

	text_w := text_width(ctx.ui.font, text)
	text_h := ctx.ui.font.metrics.line_height

	viewport := findViewport(parent)

	button.pos = Vec2 {
		viewport.viewportContext.startX + offset.x,
		viewport.viewportContext.startY + offset.y,
	}
	button.rect = Rect{button.pos, Vec2{text_w + padding_x * 2, text_h + padding_y * 2}}

	viewport.viewportContext.startX += button.rect.max.x + offset.x + 8

	addChild(parent, button)

	return button
}

findViewport :: proc(start: ^UIElement) -> ^UIElement {
	if start.kind == .Viewport do return start

	return findViewport(start.parent)
}

addViewport :: proc(ctx: ^Context, parent: ^UIElement) -> ^UIElement {

	id := ctx.ui.id
	ctx.ui.id += 1

	window := new(UIElement)
	window.kind = .Viewport
	window.viewportContext = ViewportContext{0, 0}

	window.style = DefaultStyle
	window.style.color = {166, 0, 5, 128}


	return window

}

addText :: proc(
	ctx: ^Context,
	parent: ^UIElement,
	text: string,
	zIndex: i32,
	style: UIStyle,
) -> ^UIElement {

	id := ctx.ui.id
	ctx.ui.id += 1

	el := new(UIElement)
	el.kind = .Text
	el.text = text
	el.stagedText = text
	el.style = style

	text_w := text_width(ctx.ui.font, text)
	text_h := ctx.ui.font.metrics.line_height

	viewport := findViewport(parent)

	el.pos = Vec2{viewport.viewportContext.startX, viewport.viewportContext.startY}
	el.rect = Rect{el.pos, Vec2{text_w, text_h}}

	viewport.viewportContext.startX += text_w + 8

	addChild(parent, el)

	return el
}

addChild :: proc(parent: ^UIElement, child: ^UIElement) {
	append(&parent.children, child)
	child.parent = parent
}
