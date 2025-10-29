#version 450

layout(location = 0) in vec2 fragUV;
layout(location = 1) in vec4 fragColor;

layout(location = 0) out vec4 outColor;

// Push constant: color
layout(push_constant) uniform PushConstFrag {
    mat4 dummyModel; // to match offset in layout
    vec4 color;
} pc;

layout(set = 0, binding = 0) uniform sampler2D fontAtlas;

void main() {
    vec4 texColor = vec4(1.0);
    if (fragUV != vec2(0.0)) {
        texColor = texture(fontAtlas, fragUV);
    }
    outColor = texColor * pc.color * fragColor;
}
