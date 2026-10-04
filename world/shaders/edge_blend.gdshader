shader_type canvas_item;
// Fondu entre sols texturés (herbe, sable, désert…). Chaque sol a un « poids » qui vaut 1
// au cœur de ses cases et diminue en douceur sur environ une case autour. Chaque pixel
// mélange les sols selon leur part du poids total : plus de frontière brutale, et le
// mélange reste juste même là où trois sols se rencontrent.
//
// Les couches "Edge<n>" sont dessinées dans l'ordre de la liste des biomes. La couche du sol
// n a pour opacité poids_n / (poids_n + poids des sols dessinés avant elle) : empilées,
// elles donnent exactement ce mélange proportionnel.
// Appliqué à chaque couche "Edge<n>" créée par world_generator.gd (_paint_transitions).

#include "res://world/shaders/noise.gdshaderinc"

// --- Paramètres, envoyés par world_generator.gd ---
// Poids de ce sol, 1 pixel par case, lu en interpolation linéaire.
uniform sampler2D weight : filter_linear;
// Somme des poids des sols texturés dessinés avant celui-ci (même format).
uniform sampler2D lower_weight : filter_linear;
// Taille de la carte en pixels, pour passer de la position dans le monde aux textures.
uniform vec2 map_pixels = vec2(1.0);
// Netteté du fondu : 0 = mélange très progressif, 0.5 = frontière nette.
uniform float sharpness = 0.2;
// Déformation de la frontière : les poids sont lus un peu à côté du pixel, selon un bruit,
// pour que la frontière ondule au lieu de suivre la grille des cases. Le même décalage est
// utilisé par toutes les couches : les sols voisins restent cohérents entre eux.
uniform vec2 warp_offset = vec2(0.0);
// Taille des ondulations : plus petit = ondulations plus larges.
uniform float warp_scale = 0.01;
// Amplitude des ondulations, en pixels.
uniform float warp_amount = 24.0;
// Couche qui prolonge une variante (Variant<k>) : on la découpe aussi en taches, avec les
// mêmes réglages que la couche Variant<k>, pour que les taches continuent dans le fondu.
uniform bool use_variant = false;
uniform vec2 variant_offset = vec2(0.0);
uniform float variant_scale = 0.003;
uniform float variant_threshold = 0.5;
uniform float variant_softness = 0.08;

// Décalage entre les deux bruits de la déformation (axe x et axe y).
const vec2 WARP_Y_SHIFT = vec2(57.3, 91.7);
// fbm reste surtout entre 0.35 et 0.65 : ce facteur ramène (fbm - 0.5) vers -1..1.
const float WARP_GAIN = 6.0;
// Poids en dessous duquel un sol est considéré absent (évite une division par 0).
const float MIN_WEIGHT = 0.001;

// Position du pixel dans le monde (voir variant_blend.gdshader).
varying vec2 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	vec2 p = world_pos * warp_scale + warp_offset;
	vec2 warp = vec2(fbm(p), fbm(p + WARP_Y_SHIFT)) - 0.5;
	vec2 uv = (world_pos + warp * WARP_GAIN * warp_amount) / map_pixels;
	float w = texture(weight, uv).r;
	float lower = texture(lower_weight, uv).r;
	// Part de ce sol parmi lui et ceux du dessous (1 s'il est seul).
	float share = w > MIN_WEIGHT ? w / (w + lower) : 0.0;
	// Resserre le fondu autour de 50 % selon `sharpness`.
	COLOR.a *= smoothstep(sharpness, 1.0 - sharpness, share);
	// Même calcul que variant_blend.gdshader.
	if (use_variant) {
		float v = fbm(world_pos * variant_scale + variant_offset);
		COLOR.a *= smoothstep(variant_threshold - variant_softness, variant_threshold + variant_softness, v);
	}
}
