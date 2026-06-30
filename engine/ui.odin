package engine

import "core:fmt"
import vk "vendor:vulkan"

DefaultStyle :: UIStyle {
	color            = Vec4{255, 1, 1, .1},
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
	vertexBuffers:    [MAX_FRAMES_IN_FLIGHT]Buffer,
	vertices:         [dynamic]TextVertex,
	hovered:          ^UIElement,
	active:           ^UIElement,
	minMaxCache:      map[i32]Rect,
}

UIStyle :: struct {
	color:            Vec4,
	border_radius:    f32,
	border_thickness: f32,
	font_size:        f32,
}

UIElement :: struct {
	id:         i32,
	kind:       UIKind,
	rect:       Rect,
	offset:     Vec2,
	pos:        Vec2,
	hovered:    bool,
	pressed:    bool,
	focused:    bool,
	parent:     ^UIElement,
	children:   [dynamic]^UIElement,
	style:      UIStyle,
	text:       string,
	stagedText: string,
	state:      UIState,
	onClick:    proc(ctx: ^Context, el: ^UIElement),
	layout:     UILayout,
	width:      UISize,
	height:     UISize,
	padding:    f32,
	marging:    f32,
	type:       ViewportType,
}

UIState :: bit_set[UIStateFlag]
UIStateFlag :: enum {
	Normal,
	Hovered,
	Pressed,
	Focused,
}

UILayout :: enum {
	Horizontal,
	Vertical,
}


ViewportType :: enum {
	Normal,
	Render,
	Fullscreen,
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

Flex :: enum {
	Grow,
}

Pixels :: struct {
	value: f32,
}

Percent :: struct {
	value: f32,
}

UISize :: union {
	Pixels,
	Percent,
	Flex,
}

layout :: proc(ctx: ^Context, el: ^UIElement) {

	if el == nil do return

	parentWidth := el.rect.max.x - el.rect.min.x
	parentHeight := el.rect.max.y - el.rect.min.y

	fixed: f32 = 0
	flexCount := 0


	for child in el.children {

		size := child.width

		if el.layout == .Vertical {
			size = child.height
		}
		switch val in size {
		case Pixels:
			fixed += val.value
		case Percent:
			if el.layout == .Horizontal {
				fixed += parentWidth * val.value / 100
			} else {
				fixed += parentHeight * val.value / 100
			}
		case Flex:
			flexCount += 1
		}
	}

	remaining: f32

	if el.layout == .Horizontal {
		remaining = parentWidth - fixed
	} else {
		remaining = parentHeight - fixed
	}

	flexSize: f32 = 0

	if flexCount > 0 {
		flexSize = remaining / cast(f32)flexCount
	}
	cursorX := el.rect.min.x
	cursorY := el.rect.min.y

	for child in el.children {

		width := parentWidth
		height := parentHeight

		switch el.layout {

		case .Horizontal:
			switch val in child.width {
			case Pixels:
				width = val.value
			case Percent:
				width = parentWidth * val.value / 100
			case Flex:
				width = flexSize
			}

			child.rect = Rect{{cursorX, cursorY}, {cursorX + width, cursorY + height}}

			cursorX += width

		case .Vertical:
			switch val in child.height {
			case Pixels:
				height = val.value

			case Percent:
				height = parentHeight * val.value / 100

			case Flex:
				height = flexSize
			}

			child.rect = Rect{{cursorX, cursorY}, {cursorX + width, cursorY + height}}
			cursorY += height
		}


		child.pos = child.rect.min

		layout(ctx, child)
	}
}

UISetHovered :: proc(ctx: ^Context, el: ^UIElement) -> bool {
	contains :: proc(min, max, p: Vec2) -> bool {
		return p.x >= min.x && p.x <= max.x && p.y >= min.y && p.y <= max.y}


	if el == nil {
		return false
	}

	el.state = {}

	mouse_pos := Vec2{cast(f32)ctx.platform.mousePos.x, cast(f32)ctx.platform.mousePos.y}

	child_hit := false
	for &child in el.children {
		if UISetHovered(ctx, child) {
			child_hit = true
		}
	}

	hit := false
	if el.kind != .Viewport && contains(el.rect.min, el.rect.max, mouse_pos) {
		el.state = {.Hovered}
		ctx.ui.hovered = el
		hit = true
	}

	if hit do fmt.printf("id %d hovered=%t\n", el.id, hit)

	return hit || child_hit
}

addButton :: proc(ctx: ^Context, parent: ^UIElement, text: string, style: UIStyle) -> ^UIElement {

	el := createUIElement(ctx, .Button)

	el.text = text
	el.stagedText = text
	el.style = style

	el.width = Pixels{text_width(ctx.ui.font, text)}
	el.height = Pixels{ctx.ui.font.metrics.line_height}

	addChild(parent, el)

	return el
}

findViewport :: proc(start: ^UIElement) -> ^UIElement {
	if start.kind == .Viewport do return start

	return findViewport(start.parent)
}

findGameWindow :: proc(ctx: ^Context, el: ^UIElement) -> ^UIElement {
	if el == nil do return nil

	if el.type == .Render {
		return el
	}

	for child in el.children {
		if child == nil do continue

		result := findGameWindow(ctx, child)
		if result != nil do return result
	}

	return nil
}

addViewport :: proc(
	ctx: ^Context,
	parent: ^UIElement,
	type: ViewportType,
	width: UISize,
	height: UISize,
) -> ^UIElement {

	el := createUIElement(ctx, .Viewport)

	el.width = width
	el.height = height

	el.style = DefaultStyle
	el.type = type

	if type == .Render {
		el.style.color = {255, 0, 0, .1}
	}

	if parent != nil {
		addChild(parent, el)
	}

	return el
}

addText :: proc(ctx: ^Context, parent: ^UIElement, text: string, style: UIStyle) -> ^UIElement {

	el := createUIElement(ctx, .Text)

	el.text = text
	el.stagedText = text
	el.style = style

	textWidth := text_width(ctx.ui.font, text)

	el.width = Pixels{textWidth}
	el.height = Pixels{ctx.ui.font.metrics.line_height}

	addChild(parent, el)

	return el
}

addChild :: proc(parent: ^UIElement, child: ^UIElement) {
	append(&parent.children, child)
	child.parent = parent
}

createUIElement :: proc(ctx: ^Context, kind: UIKind) -> ^UIElement {
	el := new(UIElement)

	el.kind = kind
	el.layout = .Horizontal

	el.width = .Grow
	el.height = .Grow

	ctx.ui.id += 1
	el.id = ctx.ui.id

	return el
}
