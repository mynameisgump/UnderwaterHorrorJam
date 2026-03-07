shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_lambert, specular_schlick_ggx;

uniform float fresnel_power : hint_range(1.0, 8.0) = 3.0;
uniform float fresnel_strength : hint_range(0.0, 1.0) = 0.6;
uniform vec4 bubble_color : source_color = vec4(0.7, 0.88, 1.0, 1.0);

void fragment() {
	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), fresnel_power);
	ALBEDO = bubble_color.rgb;
	ALPHA = fresnel * fresnel_strength;
	ROUGHNESS = 0.05;
	SPECULAR = 0.9;
}
