package engine

import "core:math"
import "core:math/linalg"

LightContext :: struct {
	light: Light,
	ubo:   []Buffer,
}

Light :: struct {
	pos:        Vec3,
	direction:  Vec3,
	view:       Mat4,
	projection: Mat4,
}

initLight :: proc(ctx: ^Context) {
	ctx.light.light = Light {
		pos        = Vec3{10, 20, 10},
		direction  = linalg.normalize(Vec3{-0.5, -1.0, -0.3}),
		view       = Mat4(1),
		projection = linalg.matrix_ortho3d_f32(-30, 30, -30, 30, 1, 100),
	}

	ctx.light.light.view = linalg.matrix4_look_at_f32(
		ctx.light.light.pos,
		ctx.light.light.pos + ctx.light.light.direction,
		Vec3{0, 1, 0},
	)
}
