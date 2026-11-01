shader_type spatial;
// Eau low-poly : vagues douces, facettes plates (normale calculée par face).
render_mode blend_mix, cull_disabled, depth_draw_opaque, specular_schlick_ggx;

uniform vec4 calm_color : source_color = vec4(0.16, 0.55, 0.78, 0.88);
uniform vec4 storm_color : source_color = vec4(0.10, 0.24, 0.42, 0.93);
uniform float tension : hint_range(0.0, 1.0) = 0.0;
uniform float wave_height = 0.05;

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float amp = wave_height * (1.0 + tension * 1.5);
	VERTEX.y += sin(w.x * 1.4 + TIME * 1.3) * amp + cos(w.z * 1.7 + TIME * 1.0) * amp;
}

void fragment() {
	vec3 n = normalize(cross(dFdx(VERTEX), dFdy(VERTEX)));
	if (n.z < 0.0) {
		n = -n;
	}
	NORMAL = n;
	vec4 c = mix(calm_color, storm_color, tension);
	ALBEDO = c.rgb;
	ALPHA = c.a;
	ROUGHNESS = 0.25;
}
