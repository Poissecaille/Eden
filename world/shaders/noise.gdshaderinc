// Fonctions de bruit utilisées par variant_blend.gdshader.

// Nombre de couches de bruit additionnées par fbm() : plus = contours plus détaillés.
const int FBM_OCTAVES = 4;

// Donne une direction pseudo-aléatoire pour un coin de grille.
// Toujours le même résultat pour le même coin (c'est ce qui rend le bruit stable).
vec2 hash(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return -1.0 + 2.0 * fract(sin(p) * 43758.5453123);
}

// Bruit de gradient (famille du bruit de Perlin) : valeur lisse entre environ -1 et 1.
float gradient_noise(vec2 p) {
	vec2 i = floor(p);  // case de grille contenant le point
	vec2 f = fract(p);  // position du point dans cette case (0..1)
	vec2 u = f * f * (3.0 - 2.0 * f);  // courbe lissée pour éviter les cassures entre cases
	// Influence de chacun des 4 coins, mélangée selon la position du point.
	return mix(mix(dot(hash(i), f), dot(hash(i + vec2(1.0, 0.0)), f - vec2(1.0, 0.0)), u.x),
			mix(dot(hash(i + vec2(0.0, 1.0)), f - vec2(0.0, 1.0)),
				dot(hash(i + vec2(1.0, 1.0)), f - vec2(1.0, 1.0)), u.x), u.y);
}

// Additionne FBM_OCTAVES couches de bruit de plus en plus fines : grandes formes + contours détaillés.
// Résultat ramené entre 0 et 1 (centré sur 0.5).
float fbm(vec2 p) {
	float value = 0.0;
	float amplitude = 0.5;
	for (int k = 0; k < FBM_OCTAVES; k++) {
		value += amplitude * gradient_noise(p);
		p *= 2.0;          // couche suivante 2 fois plus fine…
		amplitude *= 0.5;  // …et 2 fois moins forte
	}
	return value * 0.5 + 0.5;
}
