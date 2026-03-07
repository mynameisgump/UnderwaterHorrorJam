shader_type spatial;
render_mode cull_disabled, diffuse_lambert, specular_schlick_ggx;

uniform sampler2D normal_map_texture : hint_normal;
uniform vec3 water_color : source_color = vec3(0.06, 0.2, 0.36);
uniform vec3 custom_sky_color : source_color = vec3(0.4, 0.7, 1.0);
uniform float sky_brightness : hint_range(0.0, 5.0) = 1.2;

// Fog Parameters (Match these to your Environment settings)
uniform vec3 fog_color : source_color = vec3(0.05, 0.15, 0.25);
uniform float fog_density : hint_range(0.0, 1.0) = 0.01;
uniform float fog_aerial_perspective : hint_range(0.0, 1.0) = 1.0;

uniform float index_of_refraction = 1.333;
uniform float wave_scale = 0.002;

varying vec2 world_uv;
varying float vertex_dist;

float snells_window(vec3 normal, vec3 view, float ior) {
    float cos_theta = dot(normal, view);
    return step(sqrt(1.0 - cos_theta * cos_theta) * ior, 1.0);
}

void vertex() {
    world_uv = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz * wave_scale;
    // Calculate distance from camera to vertex for manual fog
    vertex_dist = length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
}

void fragment() {
    // 1. Setup Normals
    float time = TIME * 0.05;
    vec3 n1 = texture(normal_map_texture, world_uv + vec2(-1, 1) * time).xyz * 2.0 - 1.0;
    vec3 n2 = texture(normal_map_texture, -world_uv + vec2(0, 1) * time).xyz * 2.0 - 1.0;
    vec3 normal_map = vec3(n1.xy + n2.xy, 0.0);
    normal_map.z = sqrt(max(0.0, 1.0 - dot(normal_map.xy, normal_map.xy)));
    
    vec3 final_normal = normalize(mix(NORMAL, TANGENT * normal_map.x + BINORMAL * normal_map.y + NORMAL * normal_map.z, 1.0));

    // 2. Snell's Window Logic
    float mask = snells_window(final_normal, VIEW, index_of_refraction);
    
    // 3. Manual Fog Calculation (Exponential)
    // This allows the "water" parts to fade into the fog while the "sky" stays clear
    float fog_amount = 1.0 - exp(-vertex_dist * fog_density);
    fog_amount = clamp(fog_amount, 0.0, 1.0);

    if(!FRONT_FACING) {
        // Apply fog to the water color, but NOT to the sky color
        vec3 fogged_water = mix(water_color, fog_color, fog_amount);
        vec3 final_sky = custom_sky_color * sky_brightness;
        
        // Inside the window = Sky, Outside = Fogged Water
        ALBEDO = mix(fogged_water, final_sky, mask);
        
        // Use Emission for the sky so it "glows" through the fog
        EMISSION = mix(vec3(0.0), final_sky * 0.5, mask);
    } else {
        // Top side logic (reflection of sky)
        ALBEDO = mix(custom_sky_color, fog_color, fog_amount);
    }
}