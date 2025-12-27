#version 450

layout(set = 1, binding = 0) uniform sampler2D texSampler;

layout(set = 1, binding = 1) uniform Material {
    vec4 color;
    vec4 params; // params.x = useTexture (0 or 1)
} material;

layout(location = 1) in vec2 fragTexCoord;
layout(location = 0) out vec4 outColor;

void main() {
    vec4 texColor = texture(texSampler, fragTexCoord);

    bool useTexture = (material.params.x != 0.0);

    outColor = useTexture
        ? texColor
        : material.color;
}