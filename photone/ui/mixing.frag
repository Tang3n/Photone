#version 440
// The neural denoiser's preview (Denoise.qml): the photo as it was and the net's result, with
// a share of what the net took away given back, as denoise.Denoised.mixed does it for the
// file. In the net's own terms, where noise is as strong at any brightness: `color` is the
// share kept away of what differs between the three colors (color noise), `grain` of what
// they have in common. 1 and 1: the net's result; 0 and 0: the photo as it was.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float color;
    float grain;
    mat4 toCam;      // Rec.2020 -> the camera's own colors (upper 3x3)
    mat4 fromCam;    // and back
    vec4 scale;      // v = scale * sqrt(camera + offset)
    vec4 offset;
};
layout(binding = 1) uniform sampler2D noisy;
layout(binding = 2) uniform sampler2D clean;

vec3 into(vec3 c) { return scale.rgb * sqrt(max(mat3(toCam) * c + offset.rgb, vec3(0.0))); }

void main() {
    vec3 was = into(texture(noisy, qt_TexCoord0).rgb), now = into(texture(clean, qt_TexCoord0).rgb);
    vec3 removed = was - now;
    float shared_ = (removed.r + removed.g + removed.b) / 3.0;
    vec3 v = max(now + (1.0 - grain) * shared_ + (1.0 - color) * (removed - shared_), vec3(0.0)) / scale.rgb;
    fragColor = vec4(clamp(mat3(fromCam) * (v * v - offset.rgb), 0.0, 1.0), 1.0);
}
