shader_type canvas_item;
// Teinte du sol au pied des montagnes : l'herbe s'assombrit et jaunit en approchant des
// massifs (altitude, sol plus sec, ombre des reliefs), au lieu de rester vert vif jusqu'au
// pied des sprites.
// Appliqué au nœud "Foothills" (un rectangle couvrant la carte) créé par world_generator.gd.
// Mode « multiplier » : la couleur du rectangle multiplie ce qui est déjà dessiné (le sol).
render_mode blend_mul;

#include "res://world/shaders/noise.gdshaderinc"

// --- Paramètres, envoyés par world_generator.gd ---
// Masque des montagnes, 1 pixel par case, flouté sur plusieurs cases (1 = montagne).
uniform sampler2D mask : filter_linear;
// Poids de la mer (même texture que pour l'écume) : l'eau n'est pas teintée.
uniform sampler2D sea_weight : filter_linear;
// Taille de la carte en pixels.
uniform vec2 map_pixels = vec2(1.0);
// Couleur multipliée au plus près des montagnes (blanc = aucun effet).
uniform vec4 tint : source_color = vec4(0.86, 0.8, 0.62, 1.0);
// Irrégularité du bord de la zone teintée.
uniform vec2 noise_offset = vec2(0.0);
uniform float noise_scale = 0.01;

// fbm reste surtout entre 0.35 et 0.65 : ce facteur ramène (fbm - 0.5) vers -1..1.
const float NOISE_GAIN = 6.0;
// Part du masque déplacée par le bruit (bord plus ou moins avancé selon l'endroit).
const float NOISE_AMOUNT = 0.15;

varying vec2 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	vec2 uv = world_pos / map_pixels;
	float m = texture(mask, uv).r;
	float n = (fbm(world_pos * noise_scale + noise_offset) - 0.5) * NOISE_GAIN;
	float k = smoothstep(0.0, 0.85, m + n * NOISE_AMOUNT);
	// Pas de teinte sur l'eau.
	k *= 1.0 - smoothstep(0.3, 0.7, texture(sea_weight, uv).r);
	COLOR = mix(vec4(1.0), tint, k);
}
