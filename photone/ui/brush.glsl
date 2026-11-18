// A painted stroke while it is made, as three numbers a pixel (brush.frag keeps them, in a
// float texture): what lies under the piece of the stroke under way (x), what the piece
// before that one painted (y), and what this one has so far (z). `laid` is the mask they come
// to: edit.Painter's arithmetic (photone/edit.py, `_stretch`), which says why it is this.
float laid(vec3 state, float erase) {
    float more = (max(state.z, state.y) - state.y) / max(1.0 - state.y, 1e-6);
    return erase > 0.5 ? state.x * (1.0 - more) : 1.0 - (1.0 - state.x) * (1.0 - more);
}
