#version 330
// Simple lighting, fragment stage: one "key" light from a fixed direction,
// plus soft light from the sky (so surfaces facing up are a bit brighter than
// those facing down), plus a little ambient light so nothing is pitch black.
in vec2 fragTexCoord;
in vec4 fragColor;
in vec3 fragNormal;
uniform sampler2D texture0;
uniform vec4 colDiffuse;
uniform vec3 uLightDir;   // direction TOWARD the key light, in world space
out vec4 finalColor;
void main() {
    vec4 base = texture(texture0, fragTexCoord) * colDiffuse * fragColor;
    vec3 n = normalize(fragNormal);
    float key = max(dot(n, normalize(uLightDir)), 0.0);
    float sky = 0.5 + 0.5 * n.y;
    float light = 0.22 + 0.25 * sky + 0.6 * key;
    finalColor = vec4(base.rgb * light, base.a);
}
