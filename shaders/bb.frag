#version 450

layout(location = 0) in vec3 fragColor; // Input color from vertex shader

layout(location = 0) out vec4 outColor; // Output color to framebuffer

void main() {
    // Output the bounding box color
    outColor = vec4(1.0, 0.0, 1.0, 1.0); // Use the input color with full opacity
}