shader_type canvas_item;
// Écume le long des côtes, entre la terre et l'eau.
// La bande foam_strip.png est le profil de l'écume de la tuile de côte (sources/water_sheet.jpg),
// redressé : de haut en bas, dentelle de bulles (côté mer) puis ligne blanche, qui vient
// mordre un peu sur la terre. On la déroule perpendiculairement au rivage (v) et le long du
// rivage (u).
// Appliqué au nœud "Foam" (un rectangle couvrant la carte) créé par world_generator.gd.

#include "res://world/shaders/noise.gdshaderinc"

// --- Paramètres, envoyés par world_generator.gd ---
// Poids additionnés de la terre et de la mer (ceux des fondus, edge_blend.gdshader).
uniform sampler2D land_weight : filter_linear;
uniform sampler2D sea_weight : filter_linear;
// Profil de l'écume, répété le long du rivage.
uniform sampler2D strip : filter_nearest, repeat_enable;
// Taille de la carte en pixels.
uniform vec2 map_pixels = vec2(1.0);
// Même déformation que les fondus : l'écume suit exactement la frontière visible.
uniform vec2 warp_offset = vec2(0.0);
uniform float warp_scale = 0.01;
uniform float warp_amount = 24.0;
// Position de la bande en part de terre (0 = pleine mer, 1 = pleine terre, 0.5 = côte
// visible) : le haut de la bande (côté mer) et le bas (côté terre). La ligne blanche occupe
// environ 58 à 75 % de la bande : elle tombe ainsi entre 0.53 et 0.61, juste côté terre,
// pour couvrir la frange claire du fondu entre l'eau et la terre.
uniform float sea_side = 0.29;
uniform float land_side = 0.71;

// Mêmes constantes que edge_blend.gdshader.
const vec2 WARP_Y_SHIFT = vec2(57.3, 91.7);
const float WARP_GAIN = 6.0;
// En dessous de ce poids total (sol sans texture), pas d'écume.
const float MIN_WEIGHT = 0.05;

varying vec2 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	vec2 p = world_pos * warp_scale + warp_offset;
	vec2 warp = vec2(fbm(p), fbm(p + WARP_Y_SHIFT)) - 0.5;
	vec2 uv = (world_pos + warp * WARP_GAIN * warp_amount) / map_pixels;
	float land = texture(land_weight, uv).r;
	float sea = texture(sea_weight, uv).r;
	float total = land + sea;
	// Part de terre : 0 côté mer, 1 côté terre.
	float d = total > MIN_WEIGHT ? land / total : 0.0;
	// Position dans la bande (v = 0 côté mer, 1 côté terre).
	float v = (d - sea_side) / (land_side - sea_side);
	if (total <= MIN_WEIGHT || v < 0.0 || v > 1.0) {
		COLOR = vec4(0.0);
	} else {
		// Direction du rivage : la bande est lue le long de x pour une côte plutôt
		// horizontale, le long de y pour une côte plutôt verticale, et un mélange entre les deux.
		vec2 grad = vec2(dFdx(d), dFdy(d));
		vec2 n = abs(grad) / max(abs(grad.x) + abs(grad.y), 1e-6);
		float size_x = float(textureSize(strip, 0).x);
		vec4 along_x = texture(strip, vec2(world_pos.x / size_x, v));
		vec4 along_y = texture(strip, vec2(world_pos.y / size_x, v));
		// n.y grand = la part de terre varie surtout en y = côte horizontale = lecture en x.
		vec4 foam = mix(along_y, along_x, smoothstep(0.3, 0.7, n.y));
		// Estompe l'écume là où ni la terre ni la mer ne dominent nettement (poids total faible).
		foam.a *= smoothstep(MIN_WEIGHT, 0.3, total);
		COLOR = foam;
	}
}
