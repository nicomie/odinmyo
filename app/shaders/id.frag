#version 450

layout(location = 0) in flat uint inId;  // Input from vertex shader
layout(location = 0) out vec4 outColor;

vec3 encodeID(uint id) {
    return vec3(
        float((id >> 16) & 0xFF) / 255.0,
        float((id >> 8) & 0xFF) / 255.0,
        float(id & 0xFF) / 255.0
    );
}

void main() {
    outColor = vec4(encodeID(inId), 1.0);
}