class_name TreeScatter
extends Node2D
## Dessine des arbres (sprites détourés de trees_atlas.png) posés par world_generator.gd.
## Tous les arbres sont dessinés en une seule passe dans _draw(), triés de haut en bas :
## un arbre plus bas à l'écran passe devant celui du dessus.

# Image contenant tous les arbres, sur fond transparent.
@export var texture: Texture2D
# Rectangle de chaque arbre dans `texture` (position x, y et taille en pixels).
@export var regions: Array[Rect2i] = []

# Arbres à dessiner : [pied de l'arbre (Vector2), index dans `regions`, retourné (bool)].
var _trees: Array = []


## Remplace la liste des arbres puis redessine.
func set_trees(trees: Array) -> void:
	_trees = trees
	# Tri par hauteur du pied : ceux du dessus d'abord, ceux du bas par-dessus.
	_trees.sort_custom(func(a, b): return a[0].y < b[0].y)
	queue_redraw()


func _draw() -> void:
	if texture == null:
		return
	for tree in _trees:
		var foot: Vector2 = tree[0]
		var region: Rect2i = regions[tree[1]]
		var size := Vector2(region.size)
		# Le pied de l'arbre (bas-centre du sprite, ombre comprise) est posé sur `foot`.
		var rect := Rect2(foot - Vector2(size.x / 2.0, size.y), size)
		if tree[2]:
			# Largeur négative = sprite retourné horizontalement (plus de variété).
			rect = Rect2(rect.position.x + size.x, rect.position.y, -size.x, size.y)
		draw_texture_rect_region(texture, rect, Rect2(region))
