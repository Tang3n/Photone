// OKLab and the way out to the screen, shared by the shaders (photone/shaders.py pastes this
// file in where a shader says #include). Working colors are linear Rec.2020.
//
// OKLab is made of the cube roots of three cone signals. Lightness is a weighted sum of those
// roots whose weights add to one, so adding an amount to all three roots changes lightness by
// that amount and leaves hue and chroma (a, b) alone.
const mat3 TO_LMS = mat3(0.6166703, 0.2650725, 0.1000613, 0.3602644, 0.6358695, 0.2038777, 0.0230653, 0.0990580, 0.6960610);
const mat3 FROM_LMS = mat3(2.1402358, -0.8846276, -0.0485576, -1.2467417, 2.1631577, -0.4543695, 0.1065060, -0.2785301, 1.5029271);
const vec3 LIGHTNESS = vec3(0.2104542553, 0.7936177850, -0.0040720468);
// The roots to (L, a, b) and back (columns).
const mat3 ROOTS_TO_LAB = mat3(0.2104542553, 1.9779984951, 0.0259040371, 0.7936177850, -2.4285922050, 0.7827717662, -0.0040720468, 0.4505937099, -0.8086757660);
const mat3 LAB_TO_ROOTS = mat3(1.0, 1.0, 1.0, 0.3963377774, -0.1055613458, -0.0894841775, 0.2158037573, -0.0638541728, -1.2914855480);

vec3 rootsOf(vec3 c) {
    vec3 lms = TO_LMS * c;
    return sign(lms) * pow(abs(lms), vec3(1.0 / 3.0));
}
vec3 fromRoots(vec3 roots) { return FROM_LMS * (roots * roots * roots); }

// Linear Rec.2020 to linear sRGB (columns), and sRGB's encoding.
const mat3 TO_SRGB = mat3(1.6605, -0.1246, -0.0182, -0.5876, 1.1329, -0.1006, -0.0728, -0.0083, 1.1187);
vec3 encode(vec3 c) {
    return mix(12.92 * c, 1.055 * pow(c, vec3(1.0 / 2.4)) - 0.055, step(0.0031308, c));
}
