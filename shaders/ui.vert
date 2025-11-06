#version 450

layout(location = 0) in vec2 inPos;    
layout(location = 1) in vec2 inUV;     
layout(location = 2) in vec3 inColor;

layout(location = 0) out vec2 fragUV;
layout(location = 1) out vec3 fragColor;

layout(push_constant) uniform PushConst {
    vec2 screen_size;
} pc;

void main() {
    fragUV = inUV;
    fragColor = inColor;
    
    // Correct NDC conversion for Vulkan
    vec2 ndc_pos = vec2(
        (2.0 * inPos.x / pc.screen_size.x) - 1.0,
        (1.0 - (2.0 * inPos.y / pc.screen_size.y))
    );
    
    gl_Position = vec4(ndc_pos, 0.0, 1.0);
}