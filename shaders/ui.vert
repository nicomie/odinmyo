#version 450

layout(location = 0) in vec2 inPos;    
layout(location = 1) in vec2 inUV;     
layout(location = 2) in vec4 inColor;

layout(location = 0) out vec2 fragUV;
layout(location = 1) out vec4 fragColor;

// Push constants: model matrix
layout(push_constant) uniform PushConst {
    mat4 model;
} pc;

void main() {
    fragUV = inUV;
    fragColor = inColor;
    gl_Position = pc.model * vec4(inPos, 0.0, 1.0);
}
