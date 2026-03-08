shader_type fog;
uniform float surface_y = 200.0;
uniform float max_depth = 200.0;
uniform vec4 fog_color : source_color = vec4(0.02, 0.08, 0.15, 1.0);
uniform vec3 player_pos = vec3(0.0);
uniform float tunnel_radius : hint_range(1.0, 400.0) = 20.0;
uniform float tunnel_softness : hint_range(1.0, 50.0) = 15.0;
uniform float density_multiplier : hint_range(0.0, 5.0) = 1.0;
uniform float above_surface_fog_height : hint_range(0.0, 200.0) = 40.0;
uniform float above_surface_density : hint_range(0.0, 1.0) = 0.15;

void fog() {
    float below_factor = clamp((surface_y - WORLD_POSITION.y) / max_depth, 0.0, 1.0);
    // Above the surface: thin mist that fades out with height
    float above_factor = clamp(1.0 - (WORLD_POSITION.y - surface_y) / above_surface_fog_height, 0.0, 1.0) * above_surface_density;
    float depth_factor = max(below_factor, above_factor);

    // Cone of visibility above the player, widening toward the surface
    float height_above_player = max(WORLD_POSITION.y - player_pos.y, 0.0);
    float height_ratio = clamp(height_above_player / (surface_y - player_pos.y + 0.001), 0.0, 1.0);
    float radius_at_height = tunnel_radius * (1.0 + height_ratio * 2.0);
    float horiz_dist = length(WORLD_POSITION.xz - player_pos.xz);
    float radial = smoothstep(radius_at_height - tunnel_softness, radius_at_height + tunnel_softness, horiz_dist);

    ALBEDO = fog_color.rgb;
    DENSITY = depth_factor * mix(radial, 1.0, 0.15) * fog_color.a * density_multiplier;
}