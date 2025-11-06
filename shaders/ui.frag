#version 450

layout(location = 0) in vec2 fragUV;
layout(location = 1) in vec3 fragColor;

layout(location = 0) out vec4 outColor;

layout(binding = 0) uniform sampler2D fontAtlas;

void main() {
    float alpha = texture(fontAtlas, fragUV).r;
    outColor = vec4(fragColor, alpha);
}
