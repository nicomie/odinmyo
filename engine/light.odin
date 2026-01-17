package engine

LightType :: enum { DIRECTIONAL, POINT }

Light :: struct #align(16) {
    position: Vec3,
    type: LightType,
    color: Vec3,
    intensity: f32,
}

LightUBO :: struct {
    ambient: Vec3,
    lightCount: u32,
    lights: [32]Light,
}

LightningSystem :: struct {
    data: LightUBO,
    ubo: FrameBuffer,

    directional_light: Light,
    point_lights: [dynamic]Light
}


init_lightning :: proc(ctx: ^Context) {
    lightning := &ctx.scene.lightning
    
    initFrameBuffer(ctx, &lightning.ubo, LightUBO)

    lightning.data.ambient = Vec3{0.1, 0.1, 0.1}
    lightning.data.lightCount = 0

    lightning.directional_light = Light{
        position = Vec3{0.0, -1.0, 0.0},
        type = .DIRECTIONAL,
        color = {1.0, 1.0, 1.0},
        intensity = 0.8,
    }

    addA
}