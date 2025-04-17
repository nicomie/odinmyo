#version 450

layout (location = 0) out vec4 outColor;

layout (set = 0, binding = 0) uniform IdUniform {
    uint objectId;
};

void main() {
    uint id = objectId;
    outColor = vec4(
        float((id >> 16) & 0xFF) / 255.0,
        float((id >> 8) & 0xFF) / 255.0,
        float(id & 0xFF) / 255.0,
        1.0
    );
}