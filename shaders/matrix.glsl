// Matrix mode shader for Ghostty, tuned for actually working in it:
// - unfocused windows are green, the focused one keeps more of its real colours
//   (the frame around it is drawn by Matrix.app)
// - a window where Claude is working is transparent behind the text, so the falling code
//   drawn by Matrix.app shows through (one continuous rain behind all windows);
//   when Claude waits for you the window turns solid and calm
// - the state comes from the matrix-state hook as an almost invisible background tint:
//   #000402 = waiting, #040b04 = working (no blue in it, macOS would tint the title bar blue)
// - note: in Ghostty fragCoord has its origin at the top left

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;
    vec3 orig = texture(iChannel0, uv).rgb;

    // window state from the corner (the padding has the background colour)
    vec3 corner = texture(iChannel0, vec2(3.5, 3.5) / iResolution.xy).rgb;
    float working = step(length(corner * 255.0 - vec3(4.0, 11.0, 4.0)), 3.0);   // exactly the signal colour
    float focus = iFocus > 0 ? smoothstep(0.0, 0.35, iTime - iTimeFocus) : 0.0;

    // 1) colour: green by brightness (with extra contrast), plus part of the original hue
    vec3 bg = vec3(0.0, 0.016, 0.006);
    float lum = dot(orig, vec3(0.299, 0.587, 0.114));
    float l = clamp((lum - 0.03) / 0.72, 0.0, 1.0);
    l = pow(l, 0.62);
    vec3 green = mix(vec3(0.10, 0.74, 0.30), vec3(0.86, 1.0, 0.89), smoothstep(0.62, 1.0, l));
    vec3 mono = mix(bg, green, l);
    vec3 tinted = mix(orig, orig * vec3(0.88, 1.06, 0.92), 0.4) * 1.08;
    float sat = max(orig.r, max(orig.g, orig.b)) - min(orig.r, min(orig.g, orig.b));
    float keep = mix(0.38, 0.85, focus) * smoothstep(0.04, 0.2, sat);   // greys stay green
    vec3 col = mix(mono, tinted, keep);
    // background = anything matching the corner (even if the window has a non-Matrix background)
    float isBg = max(step(lum, 0.035), step(length(orig - corner), 0.02));
    col = mix(col, bg, isBg);

    // 2) working window: the whole background evenly transparent, solid only right around the glyphs
    float alpha = 1.0;
    if (working > 0.5) {
        vec2 px = 1.0 / iResolution.xy;
        float near = 0.0;
        for (int i = -1; i <= 1; i++)
            for (int j = -1; j <= 1; j++) {
                vec3 c = texture(iChannel0, uv + vec2(float(i), float(j)) * px * 2.0).rgb;
                near = max(near, step(0.02, length(c - corner)) * step(0.035, dot(c, vec3(0.299, 0.587, 0.114))));
            }
        // fainter rain in the focused window so it does not distract while typing
        alpha = mix(1.0, mix(0.42, 0.75, focus), 1.0 - near);
    }

    fragColor = vec4(col * alpha, alpha);   // premultiplied
}
