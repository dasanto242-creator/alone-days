shader_type spatial;
// Terreno: grama, terra, rocha (nas encostas) e neve (no alto), misturados por inclinação,
// altura e ruído. Coordenadas do mundo (sem emendas entre os pedaços do terreno).
render_mode specular_schlick_ggx;

uniform sampler2D grass_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dirt_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dirt_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D snow_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D macro_noise : filter_linear_mipmap, repeat_enable;
uniform float grass_scale = 0.22;
uniform float rock_scale = 0.07;
uniform float snow_line = 118.0;

varying vec3 wpos;
varying vec3 wnorm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec2 uv = wpos.xz * grass_scale;
	float m = texture(macro_noise, wpos.xz * 0.0035).r;
	float m2 = texture(macro_noise, wpos.xz * 0.019 + vec2(0.37, 0.11)).r;
	float dist = length(VERTEX);
	// dois tamanhos da mesma textura (esconde a repetição de longe)
	vec3 g = mix(texture(grass_albedo, uv).rgb, texture(grass_albedo, uv * 0.29 + vec2(0.3, 0.7)).rgb,
		0.35 + 0.4 * smoothstep(20.0, 120.0, dist));
	g *= mix(0.78, 1.15, m) * mix(vec3(1.0), vec3(1.12, 1.05, 0.8), smoothstep(0.55, 0.85, m2) * 0.5);
	vec3 d = texture(dirt_albedo, uv * 1.25).rgb;
	vec3 gn = texture(grass_normal, uv).rgb;
	vec3 dn = texture(dirt_normal, uv * 1.25).rgb;
	float slope = 1.0 - clamp(wnorm.y, 0.0, 1.0);
	float dirt_k = clamp(smoothstep(0.68, 0.86, m2 * 0.75 + m * 0.35) * 0.55 + smoothstep(0.12, 0.3, slope), 0.0, 1.0);
	vec3 col = mix(g, d, dirt_k);
	vec3 nrm = mix(gn, dn, dirt_k);
	float rock_k = smoothstep(0.3, 0.48, slope + (m - 0.5) * 0.16) + smoothstep(70.0, 110.0, wpos.y) * 0.4;
	rock_k = clamp(rock_k, 0.0, 1.0);
	if (rock_k > 0.001) {
		// rocha projetada de dois lados (encostas não esticam a textura)
		vec3 an = abs(wnorm);
		vec2 w = an.xz / (an.x + an.z + 0.001);
		vec3 ra = texture(rock_albedo, wpos.zy * rock_scale).rgb * w.x + texture(rock_albedo, wpos.xy * rock_scale).rgb * w.y;
		vec3 rt = texture(rock_albedo, wpos.xz * rock_scale).rgb;
		ra = mix(ra, rt, clamp(wnorm.y * 1.4 - 0.2, 0.0, 1.0));
		col = mix(col, ra * mix(0.62, 0.85, m) * vec3(1.0, 0.97, 0.92), rock_k);
		nrm = mix(nrm, texture(rock_normal, wpos.xz * rock_scale).rgb, rock_k * 0.6);
	}
	float snow_k = smoothstep(snow_line - 18.0 + m * 30.0, snow_line + m * 30.0, wpos.y) * smoothstep(0.75, 0.45, slope);
	if (snow_k > 0.001) {
		col = mix(col, texture(snow_albedo, uv * 0.5).rgb, snow_k);
		nrm = mix(nrm, vec3(0.5, 0.5, 1.0), snow_k * 0.8);
	}
	ALBEDO = col;
	NORMAL_MAP = nrm;
	NORMAL_MAP_DEPTH = 1.0;
	ROUGHNESS = mix(0.95, 0.55, snow_k);
	SPECULAR = 0.3;
}
