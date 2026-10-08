#version 450

layout(location = 0) in vec3 inPosition;

layout(set = 0, binding = 0) uniform ShadowData {
    mat4 lightViewProjection;
};

layout(push_constant) uniform Object {
    mat4 model;
};

void main()
{
    gl_Position =
        lightViewProjection *
        model *
        vec4(inPosition, 1.0);
}