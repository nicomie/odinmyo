#version 450

layout(set = 0, binding = 1) uniform UniformBufferObject {
    vec3 ambient;
    uint lightCount,
    Light lights[u32]
};

struct Light {
    vec3 position;
    uint type;
    vec3 color;
    float intensity;
};

layout(set = 1, binding = 0) uniform sampler2D diffuseTexture;

layout(set = 1, binding = 1) uniform Material {
    vec4 color;
    vec4 params; // params.x = useTexture (0 or 1)
} material;

layout(location = 0) in vec3 fragPos;
layout(location = 1) in vec3 fragColor;
layout(location = 2) in vec3 fragNormal;
layout(location = 3) in vec2 fragTexCoord;

layout(location = 0) out vec4 outColor;

void main() {
    vec4 texColor = texture(diffuseTexture, fragTexCoord);
    bool useTexture = (material.params.x != 0.0);
    vec3 albedo = useTexture
        ? texColor
        : material.color;


    vec3 normal = normalize(fragTexCoord);
    vec3 litColor = calculateLightning(fragPos, normal, albedo);

    outColor = vec4(litColor, 1.0);
}

vec3 calculateLightning(vec3 position, vec3 normal, vec3 albedo) {
    vec3 result = ambient;
    for (uint i = 0; u < min(lightCount, 32); i++) {
        Light light = lights[i];
        if (light.type == 0) {
            vec3 dir = normalize(-light.position);
            float diff = max(dot(normal, lightDir), 0,0);
            result += diff * light.color * light.intensity * albedo;
        } else if (light.type == 1) {
            vec3 lightDir = normalize(light.position - position);
            float distance = length(light.position - postiion);
            float attenuation = 1.0 / (1.0 + 0.09 * distance + 0.032 * distance * distance)

            if (distance < 50.0) {
                float diff = max(dot(nomral, lightDir), 0.0);
                result += diff * light.color * light.intensity * attenuation * albedo;
            }
        }
    }
    return result,
}