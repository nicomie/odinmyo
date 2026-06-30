#version 450

layout(location = 0) in vec2 inPos;
layout(location = 1) in vec2 inUV;
layout(location = 2) in vec4 inColor;

layout(location = 0) out vec2 fragUV;
layout(location = 1) out vec4 fragColor;

layout(push_constant) uniform PushConst {
    vec2 screen_size;
} pc;

void main()
{
    fragUV = inUV;
    fragColor = inColor;

    // DON'T flip Y here - UI coordinates should match screen space
    vec2 ndc = vec2(
        (inPos.x / pc.screen_size.x) * 2.0 - 1.0,
        (inPos.y / pc.screen_size.y) * 2.0 - 1.0  // Removed the flip
    );

    gl_Position = vec4(ndc, 0.0, 1.0);
}