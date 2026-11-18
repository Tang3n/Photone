// What bars.vert and bars.frag share: the counts (a row of 256 bins, Counts.qml) and how they
// are read, smoothed.
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float linearOut;  // as in pipeline.frag
    float soft;       // how far a bin is smoothed into its neighbors (a Gaussian's sigma, in bins)
    float first;      // the bins that make the graph: from this one
    float last;       // to this one
    float ends;       // 1: bin 0 and 255 (pixels at black and at white) stand at the ends as they are
    float wrap;       // 1: the bins go round (hues)
    float centered;   // 1: a bin lies between its edges across the item; 0: bin 0 and 255 on its two edges
    float three;      // 1: red, green and blue laid over each other, each in its own color
    vec4 pick;        // otherwise: the channel of the row that is drawn,
    vec4 color;       // in this color
    vec4 red;
    vec4 green;
    vec4 blue;
};
layout(binding = 1) uniform sampler2D counts;

// The counts at bin `p` (a bin's middle is a whole number), smoothed over its neighbors: a
// count is a few hundred pixels, and drawn as counted the graph is a row of spikes (the
// owner: "I can see the point resolution on spikes").
vec4 smoothed(float p) {
    vec4 sum = vec4(0.0);
    float total = 0.0;
    float middle = floor(p + 0.5);
    for (int k = -8; k <= 8; k++) {
        float bin = middle + float(k);
        if (wrap < 0.5 && (bin < first || bin > last)) continue;
        float w = exp(-(bin - p) * (bin - p) / (2.0 * soft * soft));
        sum += w * texelFetch(counts, ivec2(int(mod(bin, 256.0)), 0), 0);
        total += w;
    }
    return total > 0.0 ? sum / total : vec4(0.0);
}
