shader_type spatial;
// Folhagem em cartões (agulhas dos pinheiros, grama, pinheiros de longe): recorte por
// transparência, balanço com o vento, normais "arredondadas" e luz atravessando as folhas.
render_mode cull_disabled, specular_schlick_ggx;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_disable;
uniform vec4 tint : source_color = vec4(1.0);
uniform float alpha_cut = 0.42;
uniform float wind_strength = 0.12;
uniform float wind_speed = 1.3;
// 0 = grama (balança a ponta), 1 = árvore (balança mais longe do tronco e no alto)
uniform float mode = 0.0;
uniform float tree_height = 10.0;
uniform float translucency = 0.4;
uniform float base_shade = 0.55;

varying float vshade;
varying vec3 vcol;

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float t = TIME * wind_speed + dot(origin.xz, vec2(0.13, 0.07));
	float w;
	if (mode < 0.5) {
		w = (1.0 - UV.y);
		w *= w;
		vshade = mix(base_shade, 1.0, 1.0 - UV.y);
		NORMAL = normalize(mix(NORMAL, vec3(0.0, 1.0, 0.0), 0.75));
	} else {
		float h = clamp(VERTEX.y / tree_height, 0.0, 1.0);
		float r = length(VERTEX.xz);
		w = h * 0.35 + r * 0.12;
		vshade = mix(base_shade, 1.0, clamp(h * 0.6 + r * 0.22, 0.0, 1.0));
		vec3 c = vec3(0.0, VERTEX.y * 0.85 + tree_height * 0.08, 0.0);
		NORMAL = normalize(mix(NORMAL, normalize(VERTEX - c), 0.8));
	}
	vec3 gust = vec3(sin(t) + 0.4 * sin(t * 2.3 + 1.7), 0.0, 0.6 * sin(t * 0.83 + 0.9)) * wind_strength * w;
	VERTEX += (inverse(MODEL_MATRIX) * vec4(gust, 0.0)).xyz;
	vcol = COLOR.rgb;
}

void fragment() {
	// mesmo lado iluminado na frente e no verso do cartão (o Godot inverte a normal no verso)
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
	vec4 c = texture(albedo_tex, UV);
	ALBEDO = c.rgb * tint.rgb * vcol * vshade;
	ALPHA = c.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_cut;
	ROUGHNESS = 0.82;
	SPECULAR = 0.25;
	BACKLIGHT = c.rgb * translucency;
}
