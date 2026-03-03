shader_type fog;
uniform float max_depth = 50.0;
uniform vec4 fog_color : source_color = vec4(0.02, 0.08, 0.15, 1.0);

void fog() {
    // Denser at depth, thinner near surface
    float depth_factor = clamp(-WORLD_POSITION.y / max_depth, 0.0, 1.0);
    ALBEDO = fog_color.rgb;
    DENSITY = depth_factor * fog_color.a;
}