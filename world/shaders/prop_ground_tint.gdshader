shader_type canvas_item;
// Appliqué au nœud Props (prop_scatter.gd).
// Les objets marqués « teintés » (buttes, touffes) prennent la couleur du sol juste sous eux,
// en gardant leur relief : sur de l'herbe foncée ils deviennent foncés, sur de l'herbe claire,
// clairs. Les autres objets (arbres, rochers) sont dessinés tels quels.
//
// prop_scatter.gd signale un objet teinté en le dessinant avec une couleur de modulation
// dont le canal bleu vaut TINT_FLAG (voir TINT_MODULATE dans prop_scatter.gd).

// Image de ce qui est déjà dessiné (le sol), avec mipmaps pour en lire la couleur moyenne.
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
// Couleur moyenne de l'herbe vers laquelle les sprites teintés ont été recolorés dans l'atlas.
uniform vec3 reference_color = vec3(0.426, 0.53, 0.226);
// Niveau de flou de la lecture du sol : plus grand = couleur moyennée sur une zone plus large
// (ignore les détails : trèfles, brins).
uniform float ground_blur_lod = 4.5;

// Valeur du canal bleu de modulation qui signale un objet teinté.
const float TINT_FLAG = 0.5;

varying float tinted;

void vertex() {
	tinted = abs(COLOR.b - TINT_FLAG) < 0.01 ? 1.0 : 0.0;
}

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	if (tinted > 0.5) {
		vec3 ground = textureLod(screen_tex, SCREEN_UV, ground_blur_lod).rgb;
		// Relief de l'objet = son écart à la couleur de référence, reporté sur le sol local.
		tex.rgb = clamp(ground * tex.rgb / reference_color, 0.0, 1.0);
	}
	COLOR = tex;
}
