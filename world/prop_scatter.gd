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

# Numéros des objets qui projettent une ombre au sol (montagnes) : leur propre silhouette,
# en noir transparent, retournée et aplatie au sol, qui les « pose » sur le sol.
@export var shadowed: Array[int] = []

# Couleur de modulation qui signale au shader un objet teinté (canal bleu = TINT_FLAG du shader).
const TINT_MODULATE := Color(1.0, 1.0, 0.5)
# Ombre au sol : la silhouette du sprite est retournée sous son pied (les sommets pointent
# vers le bas de l'écran) et aplatie à SHADOW_SQUASH de sa hauteur ; SHADOW_SKEW l'incline
# vers la droite (lumière venant du haut à gauche).
const SHADOW_SQUASH := 0.26
const SHADOW_SKEW := -0.5
# L'ombre part un peu au-dessus du pied (en fraction de la hauteur du sprite), sous la roche :
# la base des montagnes est irrégulière, l'ombre doit en sortir collée, sans liseré d'herbe.
const SHADOW_RISE := 0.22
# Bord doux : la silhouette est dessinée plusieurs fois, légèrement décalée, peu opaque.
const SHADOW_COPIES: Array[Vector2] = [Vector2(0, 0), Vector2(-3, 0), Vector2(3, 0), Vector2(0, -3)]
const SHADOW_COLOR := Color(0.0, 0.0, 0.0, 0.09)

# Objets à dessiner : [pied de l'objet (Vector2), index dans `regions`, retourné (bool)].
var _props: Array = []
# Élément de dessin des ombres, enfant de ce nœud et dessiné derrière lui. Il n'a pas le
# shader de teinte de ce nœud (qui teinterait aussi les ombres).
var _shadow_item := RID()


func _exit_tree() -> void:
	if _shadow_item.is_valid():
		RenderingServer.free_rid(_shadow_item)
		_shadow_item = RID()


## Remplace la liste des objets puis redessine.
func set_props(props: Array) -> void:
	_props = props
	# Tri par hauteur du pied : ceux du dessus d'abord, ceux du bas par-dessus.
	_props.sort_custom(func(a, b): return a[0].y < b[0].y)
	_draw_shadows()
	queue_redraw()


# Dessine l'ombre au sol de chaque objet de `shadowed`, sous tous les objets.
func _draw_shadows() -> void:
	if not _shadow_item.is_valid():
		_shadow_item = RenderingServer.canvas_item_create()
		RenderingServer.canvas_item_set_parent(_shadow_item, get_canvas_item())
		RenderingServer.canvas_item_set_draw_behind_parent(_shadow_item, true)
	RenderingServer.canvas_item_clear(_shadow_item)
	for prop in _props:
		if not prop[1] in shadowed:
			continue
		var foot: Vector2 = prop[0]
		var region: Rect2i = regions[prop[1]]
		var size := Vector2(region.size)
		# Repère de l'ombre : origine au pied, axe vertical retourné et aplati, incliné.
		RenderingServer.canvas_item_add_set_transform(_shadow_item,
				Transform2D(0.0, Vector2(1.0, -SHADOW_SQUASH), SHADOW_SKEW,
						foot - Vector2(0.0, size.y * SHADOW_RISE)))
		for offset in SHADOW_COPIES:
			# Même rectangle que dans _draw() (retourné si l'objet l'est), autour du pied.
			var rect := Rect2(offset - Vector2(size.x / 2.0, size.y), size)
			if prop[2]:
				rect.size.x = -size.x
			RenderingServer.canvas_item_add_texture_rect_region(_shadow_item, rect,
					texture.get_rid(), Rect2(region), SHADOW_COLOR)
	RenderingServer.canvas_item_add_set_transform(_shadow_item, Transform2D.IDENTITY)


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
