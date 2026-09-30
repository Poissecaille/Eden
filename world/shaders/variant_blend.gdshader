shader_type canvas_item;
// Affiche une couche de variante de texture là où un bruit continu dépasse un seuil,
// avec un fondu doux sur les bords : pas de bord en carré de tuile.
// Appliqué à chaque couche "Variant0", "Variant1"… créée par world_generator.gd.

#include "res://world/shaders/noise.gdshaderinc"

// --- Paramètres, envoyés par world_generator.gd (_prepare_variant_layers) ---
// Décalage du bruit : différent pour chaque couche, pour que les taches ne se superposent pas.
uniform vec2 noise_offset = vec2(0.0);
// Taille des taches : plus petit = taches plus grandes.
uniform float noise_scale = 0.003;
// Seuil au-dessus duquel la variante est visible (0.5 ≈ la moitié de la surface).
uniform float threshold = 0.5;
// Largeur du fondu autour du seuil (0 = bord net).
uniform float softness = 0.08;

// Position du pixel dans le monde, calculée dans vertex() et transmise à fragment().
varying vec2 world_pos;

// Exécuté pour chaque sommet : on retient sa position dans le monde.
// Le bruit dépend de la position dans le monde (pas de la tuile) : il est donc continu
// d'une tuile à l'autre, ce qui supprime les bords carrés.
void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

// Exécuté pour chaque pixel : COLOR contient déjà la couleur de la tuile lue dans l'atlas.
// On règle seulement sa transparence selon le bruit :
//   bruit sous le seuil -> transparent (on voit l'herbe de base en dessous)
//   bruit au-dessus     -> variante visible
//   entre les deux      -> fondu progressif
void fragment() {
	float n = fbm(world_pos * noise_scale + noise_offset);
	COLOR.a *= smoothstep(threshold - softness, threshold + softness, n);
}
