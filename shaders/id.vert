#version 450

layout(location = 0) in vec3 inPosition;
layout(location = 1) in vec3 inColor;
layout(location = 2) in vec2 inTexCoord;

layout(binding = 0) uniform UniformBufferObject {
    mat4 model;
    mat4 view;
    mat4 proj;
    uint objectId;  // Add object ID to your UBO
} ubo;

layout(location = 0) out flat uint outId;  // flat qualifier for integer varyings

void main() {
    outId = ubo.objectId;  // Pass ID to fragment shader
    gl_Position = ubo.proj * ubo.view * ubo.model * vec4(inPosition, 1.0);
}