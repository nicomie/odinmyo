#version 450

layout(location = 0) in vec3 inPosition; // Vertex position (3D)

layout(location = 0) out vec3 fragColor; // Output color to fragment shader

// Uniform buffer for MVP matrix
layout(binding = 0) uniform UniformBufferObject {
    mat4 model;
    mat4 view;
    mat4 proj;
} ubo;

void main() {
    // Transform the vertex position using the MVP matrix
    gl_Position = ubo.proj * ubo.view * ubo.model * vec4(inPosition, 1.0);

    // Set the bounding box color (e.g., red)
    fragColor = vec3(1.0, 0.0, 0.0); // Red color
}