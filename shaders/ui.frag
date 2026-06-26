#version 450

layout(location = 0) in vec2 fragUV;
layout(location = 1) in vec4 fragColor;

layout(location = 0) out vec4 outColor;

layout(binding = 0) uniform sampler2D fontAtlas;

void main() {
    vec3 rgb = fragColor.rgb;
    if (max(max(rgb.r, rgb.g), rgb.b) > 1.0) {
        rgb /= 255.0;
    }

    float outAlpha = fragColor.a > 1.0 ? fragColor.a / 255.0 : fragColor.a;

    float alpha;
    if (fragUV.x < 0.0 || fragUV.y < 0.0) {
        alpha = outAlpha;
    } else {
        alpha = texture(fontAtlas, fragUV).r * outAlpha;
    }
    outColor = vec4(rgb, alpha);
}
