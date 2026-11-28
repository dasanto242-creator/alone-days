shader_type sky;
// Céu: degradê, sol com halo, nuvens projetadas num plano alto (iluminadas pelo sol) e
// bruma no horizonte. Sem animação (o reflexo do céu é calculado uma vez só).

uniform vec3 zenith : source_color = vec3(0.24, 0.39, 0.62);
uniform vec3 horizon : source_color = vec3(0.68, 0.74, 0.8);
uniform vec3 ground_color : source_color = vec3(0.3, 0.31, 0.29);
uniform sampler2D cloud_noise : filter_linear_mipmap, repeat_enable;
uniform float cloud_cover = 0.52;
uniform vec3 cloud_lit : source_color = vec3(1.0, 0.97, 0.92);
uniform vec3 cloud_dark : source_color = vec3(0.52, 0.56, 0.62);

void sky() {
	vec3 d = EYEDIR;
	float y = d.y;
	vec3 col = mix(horizon, zenith, pow(clamp(y, 0.0, 1.0), 0.5));
	if (y < 0.0) {
		col = mix(horizon, ground_color, clamp(-y * 5.0, 0.0, 1.0));
	}
	float sd = max(dot(d, LIGHT0_DIRECTION), 0.0);
	vec3 sun = LIGHT0_COLOR * min(LIGHT0_ENERGY, 2.0);
	col += sun * (pow(sd, 9.0) * 0.18 + pow(sd, 90.0) * 0.35);
	if (!AT_CUBEMAP_PASS || true) {
		col += sun * smoothstep(0.9993, 0.9997, sd) * 14.0;
	}
	if (y > 0.0) {
		vec2 uv = d.xz / (y + 0.1) * 0.18;
		float n = texture(cloud_noise, uv).r * 0.62 + texture(cloud_noise, uv * 2.9 + vec2(0.31, 0.53)).r * 0.38;
		float c = smoothstep(1.0 - cloud_cover, 1.0 - cloud_cover + 0.22, n);
		float thick = smoothstep(1.0 - cloud_cover + 0.05, 1.0, n);
		vec3 cc = mix(cloud_lit, cloud_dark, thick * 0.85);
		cc += sun * pow(sd, 6.0) * 0.35 * (1.0 - thick);
		float fade = smoothstep(0.0, 0.25, y);
		col = mix(col, cc, c * fade * 0.92);
	}
	COLOR = col;
}
