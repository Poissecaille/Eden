class_name PropScatter
extends Node2D
## Dessine les objets du décor (arbres, buttes…, sprites détourés de props_atlas.png)
## posés par world_generator.gd.
## Tous les objets sont dessinés en une seule passe dans _draw(), triés de haut en bas :
## un objet plus bas à l'écran passe devant celui du dessus.

# Image contenant tous les objets, sur fond transparent.
@export var texture: Texture2D
# Rectangle de chaque objet dans `texture` (position x, y et taille en pixels).
# Les biomes désignent leurs objets par leur numéro dans cette liste (voir Biome.props).
@export var regions: Array[Rect2i] = []
# Numéros des objets qui prennent la couleur du sol sous eux (buttes, touffes).
# Nécessite le shader prop_ground_tint.gdshader sur ce nœud.
@export var ground_tinted: Array[int] = []

# Couleur de modulation qui signale au shader un objet teinté (canal bleu = TINT_FLAG du shader).
const TINT_MODULATE := Color(1.0, 1.0, 0.5)

# Objets à dessiner : [pied de l'objet (Vector2), index dans `regions`, retourné (bool)].
var _props: Array = []


## Remplace la liste des objets puis redessine.
func set_props(props: Array) -> void:
	_props = props
	# Tri par hauteur du pied : ceux du dessus d'abord, ceux du bas par-dessus.
	_props.sort_custom(func(a, b): return a[0].y < b[0].y)
	queue_redraw()


func _draw() -> void:
	if texture == null:
		return
	for prop in _props:
		var foot: Vector2 = prop[0]
		var region: Rect2i = regions[prop[1]]
		var size := Vector2(region.size)
		# Le pied de l'objet (bas-centre du sprite) est posé sur `foot`.
		var rect := Rect2(foot - Vector2(size.x / 2.0, size.y), size)
		if prop[2]:
			# Largeur négative = sprite retourné horizontalement (plus de variété).
			# Godot garde la même position de départ : pas de décalage à ajouter.
			rect.size.x = -size.x
		var modulate_color := TINT_MODULATE if prop[1] in ground_tinted else Color.WHITE
		draw_texture_rect_region(texture, rect, Rect2(region), modulate_color)
