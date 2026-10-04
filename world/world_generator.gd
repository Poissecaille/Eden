@tool
class_name WorldGenerator
extends Node2D
## Génère une carte de tuiles 2D à partir de deux bruits de Perlin :
## l'élévation (eau -> plaine -> montagne -> neige) et l'humidité (désert <-> marais/forêt).
##
## Déroulé d'une génération (voir generate()) :
##   1. on calcule deux grilles de valeurs 0..1 : élévation et humidité ;
##   2. pour chaque case, on choisit le biome qui correspond à ces deux valeurs ;
##   3. on pose la tuile du biome : une texture de l'atlas, ou une couleur unie ;
##   4. si le biome a des variantes, on les pose sur des couches au-dessus,
##      que le shader variant_blend.gdshader découpe en taches aux bords doux.
##   5. entre sols texturés (herbe, sable…), les textures se mélangent progressivement
##      (shader edge_blend.gdshader) : pas de frontière brutale en escalier ;
##   6. écume le long des côtes, entre la terre et l'eau (shore_foam.gdshader) ;
##   7. les biomes qui ont des objets (arbres en forêt, buttes en collines…) reçoivent des
##      sprites par-dessus, de plus en plus clairsemés vers leur bord.

# Émis à la fin de chaque génération (la caméra l'écoute pour se recadrer).
signal generated

## Id de la source (générée au lancement) des tuiles de couleur unie.
const COLOR_SOURCE_ID := 100
# Shader qui rend les couches de variantes visibles seulement par taches.
const VARIANT_SHADER := preload("res://world/shaders/variant_blend.gdshader")
# Shader qui fait s'effacer un sol sur son voisin (couches de transition "Edge<n>").
const EDGE_SHADER := preload("res://world/shaders/edge_blend.gdshader")
# Shader qui dessine l'écume le long des côtes (nœud "Foam").
const FOAM_SHADER := preload("res://world/shaders/shore_foam.gdshader")
# Shader qui teinte le sol au pied des montagnes (nœud "Foothills").
const FOOTHILL_SHADER := preload("res://world/shaders/foothill_tint.gdshader")

# Les graines aléatoires sont tirées entre 0 et cette valeur (exclue).
const MAX_SEED := 1_000_000
# Ajouté à la graine pour le bruit d'humidité, afin qu'il diffère de celui d'élévation.
const MOISTURE_SEED_OFFSET := 1
# Finesse et importance des détails du bruit d'humidité (voir height_lacunarity / height_gain).
const MOISTURE_LACUNARITY := 2.0
const MOISTURE_GAIN := 0.5
# Écart minimal entre valeurs min et max lors de la normalisation (évite une division par 0).
const MIN_NOISE_SPAN := 0.0001
# Mode île : distance au centre (0 = centre, 1 = bord) où l'abaissement commence / est maximal.
const ISLAND_FALLOFF_START := 0.5
const ISLAND_FALLOFF_END := 1.2
# Décalage maximal du bruit des variantes. Reste modéré : avec de grandes coordonnées,
# le bruit du shader perd en précision.
const NOISE_OFFSET_RANGE := 1000.0
# Nombre de cases autour d'un biome à objets où quelques objets peuvent déborder sur son sol.
const PROP_SPILL_RADIUS := 2
# Emplacements tirés au hasard par case pour les objets (chacun reçoit un objet ou non).
const PROP_CANDIDATES_PER_CELL := 3
# Valeur du masque flou (0 = hors du biome, 1 = en plein cœur) où les objets commencent
# à apparaître / atteignent leur pleine densité : de rares objets débordent sur le bord.
const PROP_MASK_START := 0.3
const PROP_MASK_FULL := 0.8
# Écart minimal entre deux objets d'une ceinture de contreforts (voir Biome.prop_spacing).
const FRINGE_SPACING := 0.6
# Écart minimal entre deux objets du sol (voir Biome.ground_props) : réparti régulièrement.
const GROUND_PROP_SPACING := 1.5
# Distance (en cases) autour d'une frontière entre sols texturés où les couches de fondu
# sont posées : doit couvrir la largeur du fondu (1 case) plus les ondulations.
const EDGE_RADIUS := 2

# ---------------------------------------------------------------------------
# Réglages (visibles dans l'inspecteur du nœud World)
# ---------------------------------------------------------------------------

# Couche de tuiles principale sur laquelle on dessine la carte.
@export var ground: TileMapLayer
# Texte d'aide affiché en haut de l'écran (seed + touches).
@export var info_label: Label
# Nœud qui dessine les objets du décor (arbres, buttes…) par-dessus les tuiles.
@export var props: PropScatter

# Taille de la carte, en nombre de cases.
@export var map_size := Vector2i(200, 120)
# Taille d'une case en pixels : doit être la même que celle de la TileSet (64 actuellement).
@export var tile_size := 16
# Graine du hasard : même graine = même carte.
@export var world_seed := 0
# Si coché, une graine aléatoire est tirée à chaque lancement du jeu.
@export var randomize_seed_on_start := true
## Effets graphiques (shaders) : plaques de variantes, fondus entre sols, écume des côtes,
## teinte des objets selon le sol. Décoché = tuiles brutes. Touche E en jeu.
@export var effects_enabled := true

@export_group("Élévation")
# Plus petit = reliefs plus larges (continents), plus grand = reliefs plus hachés.
@export var height_frequency := 0.025
# Nombre de couches de détails superposées au bruit.
@export_range(1, 8) var height_octaves := 5
# Facteur de finesse entre deux couches de détails.
@export var height_lacunarity := 2.0
# Importance des petits détails par rapport aux grandes formes.
@export_range(0.0, 1.0) var height_gain := 0.5

@export_group("Humidité")
@export var moisture_frequency := 0.015
@export_range(1, 8) var moisture_octaves := 3

@export_group("Forme")
## Abaisse les bords de la carte pour obtenir une île entourée d'eau.
@export var island_mode := false
# Force de l'effet île (0 = aucun, 1 = bords complètement sous l'eau).
@export_range(0.0, 1.0) var island_falloff := 0.7

@export_group("Tuiles")
# Liste des biomes, testés dans l'ordre : le premier qui correspond à une case gagne.
@export var biomes: Array[Biome] = []

@export_group("Variantes de texture")
## Taille des plaques de variantes (plus petit = plaques plus grandes).
@export var variant_scale := 0.003
## Plus haut = moins de variantes visibles (0.5 ≈ la moitié de la surface par variante).
@export_range(0.0, 1.0) var variant_threshold := 0.5
## Largeur du fondu entre deux variantes (0 = bord net).
@export_range(0.0, 0.5) var variant_softness := 0.08

@export_group("Transitions entre sols")
## Netteté du fondu entre sols texturés (0 = mélange étalé sur environ une case de chaque
## côté de la frontière, 0.5 = frontière nette).
@export_range(0.0, 0.5) var edge_sharpness := 0.2
## Amplitude des ondulations de la frontière, en pixels (0 = elle suit la grille des cases).
@export_range(0.0, 64.0) var edge_warp := 24.0
## Taille des ondulations (plus petit = ondulations plus larges).
@export var edge_warp_scale := 0.01

@export_group("Écume des côtes")
## Sols d'eau : l'écume est dessinée entre eux et tous les autres sols texturés (la terre).
## Liste vide = pas d'écume.
@export var foam_sea_biomes: Array[Biome] = []
## Profil de l'écume (dentelle puis ligne blanche), voir shore_foam.gdshader.
@export var foam_strip: Texture2D

@export_group("Pied des montagnes")
## Biomes au pied desquels le sol est teinté (liste vide = pas de teinte).
@export var foothill_biomes: Array[Biome] = []
## Couleur multipliée au sol au plus près des massifs (blanc = aucun effet).
@export var foothill_color := Color(0.86, 0.8, 0.62)
## Distance (en cases, environ) sur laquelle la teinte s'estompe.
@export_range(0, 6) var foothill_spread := 3

@export_group("Éditeur")
## Coche pour générer un aperçu directement dans l'éditeur.
@export var generate_now := false:
	set(value):
		if value and is_node_ready():
			generate()
# Coche pour effacer la carte dans l'éditeur (n'efface que `ground`, pas les variantes).
@export var clear_now := false:
	set(value):
		if value and ground:
			ground.clear()

# ---------------------------------------------------------------------------
# Données de la carte générée
# Chaque tableau contient une valeur par case, rangée ligne par ligne :
# la case (x, y) est à l'index y * map_size.x + x.
# ---------------------------------------------------------------------------

# Élévation de chaque case, entre 0 (fond de l'eau) et 1 (sommet).
var height_map := PackedFloat32Array()
# Humidité de chaque case, entre 0 (sec) et 1 (humide).
var moisture_map := PackedFloat32Array()
## Index du biome de chaque case (y * map_size.x + x), pratique pour le gameplay.
var biome_map := PackedInt32Array()

# Poids de chaque sol texturé (index du biome -> Image, 1 pixel par case), calculés par
# _paint_transitions et réutilisés pour l'écume.
var _ground_weights := {}
# Décalage de la déformation des frontières, partagé par les fondus et l'écume.
var _warp_offset := Vector2.ZERO
# Matériau (shader de teinte) du nœud des objets, mis de côté quand les effets sont coupés.
var _props_material: Material
# Vrai si la dernière génération a de l'écume à dessiner (voir _paint_foam).
var _foam_active := false
# Poids additionnés des sols d'eau (1 pixel par case), calculés par _paint_foam.
var _sea_weight: Image
# Vrai si la dernière génération a une teinte au pied des montagnes (voir _paint_foothills).
var _foothills_active := false


# Au lancement du jeu : tire une graine si demandé, puis génère la carte.
# Dans l'éditeur on ne fait rien (il faut cocher `generate_now`).
func _ready() -> void:
	if Engine.is_editor_hint():
		return
	if randomize_seed_on_start:
		world_seed = randi() % MAX_SEED
	generate()


# Touches du jeu : R = nouvelle carte, I = active/désactive le mode île,
# E = active/désactive les effets graphiques (shaders).
func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_R:
				world_seed = randi() % MAX_SEED
				generate()
			KEY_I:
				island_mode = not island_mode
				generate()
			KEY_E:
				# Pas besoin de régénérer : on montre / cache seulement les couches à shader.
				effects_enabled = not effects_enabled
				_apply_effects()
				_update_info()


# Fonction principale : (re)génère toute la carte.
func generate() -> void:
	# --- Vérifications ---
	if ground == null:
		push_error("WorldGenerator : aucun TileMapLayer assigné à 'ground'.")
		return
	# if biomes.is_empty():
	# 	biomes = default_biomes()
	if biomes.is_empty():
		push_error("WorldGenerator : la liste 'biomes' est vide.")
		return

	# --- Préparation des tuiles de couleur unie (biomes sans texture) ---
	_ensure_tileset()

	# --- Étape 1 : les deux cartes de bruit de Perlin ---
	# La graine +1 pour l'humidité évite qu'elle soit identique à l'élévation.
	height_map = _normalized(_sample(_make_noise(world_seed, height_frequency,
			height_octaves, height_lacunarity, height_gain)))
	moisture_map = _normalized(_sample(_make_noise(world_seed + MOISTURE_SEED_OFFSET,
			moisture_frequency, moisture_octaves, MOISTURE_LACUNARITY, MOISTURE_GAIN)))
	if island_mode:
		_apply_island_falloff()

	# --- Couches de variantes (vides pour l'instant, remplies dans la boucle) ---
	var layers := _prepare_variant_layers()

	# --- Étapes 2 à 4 : pour chaque case, choix du biome et pose des tuiles ---
	ground.clear()
	biome_map.resize(map_size.x * map_size.y)
	# Index du biome dont la case porte le sol (la Plaine pour une case de Forêt…).
	var ground_map := PackedInt32Array()
	ground_map.resize(map_size.x * map_size.y)
	for y in map_size.y:
		for x in map_size.x:
			var i := y * map_size.x + x

			# Étape 2 : quel biome pour cette élévation et cette humidité ?
			var b := _pick_biome(height_map[i], moisture_map[i])
			biome_map[i] = b
			var biome := biomes[b]
			var cell := Vector2i(x, y)

			# Un biome qui a un sol d'un autre biome (ex. forêt sur herbe) : on peint ce sol.
			var ground_index := b
			if biome.ground_biome != null:
				biome = biome.ground_biome
				ground_index = biomes.find(biome)
			ground_map[i] = ground_index

			if biome.atlas_coords.x >= 0:
				# Étape 3a : biome texturé.
				# Le bloc de texture fait pattern_size tuiles ; le modulo (%) fait défiler
				# les tuiles du bloc case après case, pour que la texture soit continue.
				var offset := Vector2i(x % biome.pattern_size.x, y % biome.pattern_size.y)
				ground.set_cell(cell, biome.source_id, biome.atlas_coords + offset)

				# Étape 4 : chaque variante est posée sur sa propre couche au-dessus.
				# C'est le shader qui décide ensuite quels pixels de ces couches sont visibles.
				for k in biome.extra_variants.size():
					layers[k].set_cell(cell, biome.source_id, biome.extra_variants[k] + offset)
			else:
				# Étape 3b : biome sans texture -> tuile de couleur unie n° b.
				ground.set_cell(cell, COLOR_SOURCE_ID, Vector2i(ground_index, 0))

	# --- Étape 5 : fondus entre sols texturés, au-dessus des variantes ---
	var next_index := _paint_transitions(ground_map, ground.get_index() + 1 + layers.size())

	# --- Étape 6 : écume des côtes, au-dessus des fondus ---
	_paint_foam(next_index)
	# Teinte du sol au pied des montagnes, placée juste sous l'écume.
	_paint_foothills(next_index)

	# --- Étape 7 : les objets du décor, posés par-dessus ---
	_place_props()

	_apply_effects()
	_update_info()
	generated.emit()


## Montre ou cache tout ce qui passe par un shader, selon `effects_enabled` :
## couches de variantes ("Variant<k>") et de fondus ("Edge…"), écume ("Foam"), teinte au pied
## des montagnes ("Foothills"), et teinte des objets selon le sol (matériau du nœud `props`).
## Sans effets, on voit les tuiles brutes.
func _apply_effects() -> void:
	for child in get_children():
		var child_name := String(child.name)
		if child is TileMapLayer and (child_name.begins_with("Variant") or child_name.begins_with("Edge")):
			child.visible = effects_enabled
	# L'écume reste cachée si _paint_foam l'a désactivée (pas de mer sur la carte).
	var foam := get_node_or_null("Foam") as CanvasItem
	if foam:
		foam.visible = effects_enabled and _foam_active
	var foothills := get_node_or_null("Foothills") as CanvasItem
	if foothills:
		foothills.visible = effects_enabled and _foothills_active
	if props:
		if props.material:
			_props_material = props.material
		props.material = _props_material if effects_enabled else null


## Une couche TileMapLayer par variante, au-dessus de `ground`, découpée au pixel par le shader.
## Les couches sont créées au premier appel puis réutilisées (vidées) aux générations suivantes.
func _prepare_variant_layers() -> Array[TileMapLayer]:
	# Nombre de couches nécessaires = le plus grand nombre de variantes parmi les biomes.
	var count := 0
	for biome in biomes:
		count = maxi(count, biome.extra_variants.size())

	# Tirages aléatoires déterminés par la graine : même graine = mêmes taches.
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed

	var layers: Array[TileMapLayer] = []
	for k in count:
		# On cherche la couche "Variant0", "Variant1"… et on la crée si elle n'existe pas.
		var layer_name := "Variant%d" % k
		var layer := get_node_or_null(layer_name) as TileMapLayer
		if layer == null:
			layer = TileMapLayer.new()
			layer.name = layer_name
			layer.material = ShaderMaterial.new()
			layer.material.shader = VARIANT_SHADER
			add_child(layer)
			# Placée juste après `ground` dans l'arbre = dessinée par-dessus.
			move_child(layer, ground.get_index() + 1 + k)
		layer.tile_set = ground.tile_set
		layer.clear()

		# Paramètres du shader. Le décalage du bruit est tiré au hasard pour chaque couche,
		# pour que chaque variante forme ses taches à des endroits différents.
		var mat := layer.material as ShaderMaterial
		mat.set_shader_parameter("noise_offset", Vector2(
				rng.randf_range(0.0, NOISE_OFFSET_RANGE), rng.randf_range(0.0, NOISE_OFFSET_RANGE)))
		mat.set_shader_parameter("noise_scale", variant_scale)
		mat.set_shader_parameter("threshold", variant_threshold)
		mat.set_shader_parameter("softness", variant_softness)
		layers.append(layer)
	return layers


## Fondus entre sols texturés (l'eau, sans texture, garde un bord net).
## Chaque sol texturé reçoit un poids : son masque (1 pixel par case) flouté, qui passe de
## 1 à 0 sur environ une case autour de ses cases. Une couche "Edge<n>" par sol (n = index
## du biome), plus une "Edge<n>_<k>" par variante pour que ses plaques continuent dans le
## fondu, posées sur les cases proches d'une frontière entre sols texturés. Le shader
## edge_blend.gdshader mélange les sols selon leur part du poids total (voir ce fichier).
## Les couches sont rangées à partir de `first_index` dans l'arbre, dans l'ordre de la liste.
func _paint_transitions(ground_map: PackedInt32Array, first_index: int) -> int:
	# Les couches d'une génération précédente sont vidées (un sol a pu perdre sa texture).
	for child in get_children():
		if child is TileMapLayer and String(child.name).begins_with("Edge"):
			child.clear()

	# Cases à repeindre pour chaque sol : cases texturées qui ont, à moins de EDGE_RADIUS
	# cases, ce sol ET un autre sol texturé (ailleurs, un seul sol : la couche `ground` suffit).
	var cells_by_ground := {}
	for y in map_size.y:
		for x in map_size.x:
			if biomes[ground_map[y * map_size.x + x]].atlas_coords.x < 0:
				continue
			var near := _textured_grounds_near(ground_map, x, y)
			if near.size() < 2:
				continue
			for g in near:
				if not cells_by_ground.has(g):
					cells_by_ground[g] = []
				cells_by_ground[g].append(Vector2i(x, y))

	# Même graine = mêmes fondus. Un seul décalage de déformation pour toutes les couches :
	# les sols voisins ondulent ensemble.
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed + 2
	_warp_offset = Vector2(
			rng.randf_range(0.0, NOISE_OFFSET_RANGE), rng.randf_range(0.0, NOISE_OFFSET_RANGE))
	_ground_weights.clear()

	# Somme des poids des sols texturés déjà traités (placés avant dans la liste).
	var lower := Image.create(map_size.x, map_size.y, false, Image.FORMAT_L8)
	var order := 0
	for g in biomes.size():
		var biome := biomes[g]
		if biome.atlas_coords.x < 0:
			continue

		# Poids de ce sol : son masque flouté.
		var mask := Image.create(map_size.x, map_size.y, false, Image.FORMAT_L8)
		for y in map_size.y:
			for x in map_size.x:
				if ground_map[y * map_size.x + x] == g:
					mask.set_pixel(x, y, Color.WHITE)
		var weight := _blurred(mask)
		_ground_weights[g] = weight

		if cells_by_ground.has(g):
			var weight_texture := ImageTexture.create_from_image(weight)
			var lower_texture := ImageTexture.create_from_image(lower)
			# Une couche pour la texture de base, puis une par variante : mêmes poids et même
			# déformation, donc exactement le même fondu.
			var blocks: Array[Vector2i] = [biome.atlas_coords]
			blocks.append_array(biome.extra_variants)
			for k in blocks.size():
				var layer_name := "Edge%d" % g if k == 0 else "Edge%d_%d" % [g, k - 1]
				var layer := _edge_layer(layer_name, first_index + order)
				order += 1
				var mat := layer.material as ShaderMaterial
				mat.set_shader_parameter("weight", weight_texture)
				mat.set_shader_parameter("lower_weight", lower_texture)
				mat.set_shader_parameter("map_pixels", Vector2(map_size * tile_size))
				mat.set_shader_parameter("sharpness", edge_sharpness)
				mat.set_shader_parameter("warp_offset", _warp_offset)
				mat.set_shader_parameter("warp_scale", edge_warp_scale)
				mat.set_shader_parameter("warp_amount", edge_warp)
				mat.set_shader_parameter("use_variant", k > 0)
				if k > 0:
					# Mêmes taches que la couche Variant<k-1> (voir _prepare_variant_layers).
					var variant := get_node("Variant%d" % (k - 1)) as TileMapLayer
					var variant_mat := variant.material as ShaderMaterial
					mat.set_shader_parameter("variant_offset", variant_mat.get_shader_parameter("noise_offset"))
					mat.set_shader_parameter("variant_scale", variant_scale)
					mat.set_shader_parameter("variant_threshold", variant_threshold)
					mat.set_shader_parameter("variant_softness", variant_softness)

				# Même décalage de motif que sur la couche principale : la texture prolonge
				# exactement le sol (ou sa variante).
				for cell: Vector2i in cells_by_ground[g]:
					var offset := Vector2i(cell.x % biome.pattern_size.x, cell.y % biome.pattern_size.y)
					layer.set_cell(cell, biome.source_id, blocks[k] + offset)

		# Ajoute le poids de ce sol à la somme pour les sols suivants.
		_add_image(lower, weight)
	return first_index + order


## Écume le long des côtes, entre les sols de `foam_sea_biomes` (la mer) et tous les autres
## sols texturés (la terre) : un rectangle "Foam" couvrant la carte, placé à `index` dans
## l'arbre (au-dessus des fondus), dont le shader shore_foam.gdshader ne dessine que la bande
## de la côte. Les poids additionnés de la terre et de la mer sont ceux des fondus : la
## frontière terre / mer qu'ils donnent est exactement la côte visible.
func _paint_foam(index: int) -> void:
	var foam := get_node_or_null("Foam") as ColorRect
	# Somme des poids de la mer et de la terre (1 pixel par case).
	var sea := Image.create(map_size.x, map_size.y, false, Image.FORMAT_L8)
	var land := Image.create(map_size.x, map_size.y, false, Image.FORMAT_L8)
	var has_sea := false
	for g: int in _ground_weights:
		var is_sea := biomes[g] in foam_sea_biomes
		has_sea = has_sea or is_sea
		_add_image(sea if is_sea else land, _ground_weights[g])
	_sea_weight = sea
	_foam_active = has_sea and foam_strip != null
	if not _foam_active:
		if foam:
			foam.visible = false
		return

	if foam == null:
		foam = ColorRect.new()
		foam.name = "Foam"
		foam.mouse_filter = Control.MOUSE_FILTER_IGNORE
		foam.material = ShaderMaterial.new()
		foam.material.shader = FOAM_SHADER
		add_child(foam)
	move_child(foam, index)
	foam.visible = effects_enabled
	foam.position = Vector2.ZERO
	foam.size = Vector2(map_size * tile_size)
	var mat := foam.material as ShaderMaterial
	mat.set_shader_parameter("land_weight", ImageTexture.create_from_image(land))
	mat.set_shader_parameter("sea_weight", ImageTexture.create_from_image(sea))
	mat.set_shader_parameter("strip", foam_strip)
	mat.set_shader_parameter("map_pixels", Vector2(map_size * tile_size))
	mat.set_shader_parameter("warp_offset", _warp_offset)
	mat.set_shader_parameter("warp_scale", edge_warp_scale)
	mat.set_shader_parameter("warp_amount", edge_warp)


## Teinte du sol au pied des biomes de `foothill_biomes` (montagnes, neige) : un rectangle
## "Foothills" couvrant la carte, placé à `index` dans l'arbre (au-dessus des fondus, sous
## l'écume), dont le shader foothill_tint.gdshader multiplie le sol par `foothill_color`
## près des massifs, de moins en moins sur `foothill_spread` cases.
func _paint_foothills(index: int) -> void:
	var rect := get_node_or_null("Foothills") as ColorRect
	var mask := Image.create(map_size.x, map_size.y, false, Image.FORMAT_L8)
	var any := false
	for y in map_size.y:
		for x in map_size.x:
			if biomes[biome_map[y * map_size.x + x]] in foothill_biomes:
				mask.set_pixel(x, y, Color.WHITE)
				any = true
	_foothills_active = any and foothill_spread > 0
	if not _foothills_active:
		if rect:
			rect.visible = false
		return
	# Chaque flou étale le masque d'environ une case.
	for i in foothill_spread:
		mask = _blurred(mask)

	if rect == null:
		rect = ColorRect.new()
		rect.name = "Foothills"
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rect.material = ShaderMaterial.new()
		rect.material.shader = FOOTHILL_SHADER
		add_child(rect)
	move_child(rect, index)
	rect.visible = effects_enabled
	rect.position = Vector2.ZERO
	rect.size = Vector2(map_size * tile_size)
	var sea := _sea_weight
	if sea == null:
		sea = Image.create(map_size.x, map_size.y, false, Image.FORMAT_L8)
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed + 3
	var mat := rect.material as ShaderMaterial
	mat.set_shader_parameter("mask", ImageTexture.create_from_image(mask))
	mat.set_shader_parameter("sea_weight", ImageTexture.create_from_image(sea))
	mat.set_shader_parameter("map_pixels", Vector2(map_size * tile_size))
	mat.set_shader_parameter("tint", foothill_color)
	mat.set_shader_parameter("noise_offset", Vector2(
			rng.randf_range(0.0, NOISE_OFFSET_RANGE), rng.randf_range(0.0, NOISE_OFFSET_RANGE)))


# Ajoute pixel par pixel l'image `extra` à `total` (même taille, valeurs plafonnées à 1).
func _add_image(total: Image, extra: Image) -> void:
	for y in total.get_height():
		for x in total.get_width():
			var v := minf(total.get_pixel(x, y).r + extra.get_pixel(x, y).r, 1.0)
			total.set_pixel(x, y, Color(v, v, v))


# Couche de transition `layer_name`, créée au premier appel puis réutilisée, placée à `index`.
func _edge_layer(layer_name: String, index: int) -> TileMapLayer:
	var layer := get_node_or_null(layer_name) as TileMapLayer
	if layer == null:
		layer = TileMapLayer.new()
		layer.name = layer_name
		layer.material = ShaderMaterial.new()
		layer.material.shader = EDGE_SHADER
		add_child(layer)
	move_child(layer, index)
	layer.tile_set = ground.tile_set
	return layer


# Index des sols texturés présents à moins de EDGE_RADIUS cases de (x, y), diagonales comprises.
func _textured_grounds_near(ground_map: PackedInt32Array, x: int, y: int) -> Array[int]:
	var found: Array[int] = []
	for dy in range(-EDGE_RADIUS, EDGE_RADIUS + 1):
		for dx in range(-EDGE_RADIUS, EDGE_RADIUS + 1):
			var cx := x + dx
			var cy := y + dy
			if cx < 0 or cy < 0 or cx >= map_size.x or cy >= map_size.y:
				continue
			var g := ground_map[cy * map_size.x + cx]
			if biomes[g].atlas_coords.x >= 0 and not g in found:
				found.append(g)
	return found


## Pose les objets de chaque biome qui a une `prop_density` : sur ses propres cases, et
## quelques-uns sur les cases de son `ground_biome` à moins de PROP_SPILL_RADIUS cases.
func _place_props() -> void:
	# Tirages déterminés par la graine (graine différente de celle des variantes).
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed + 1
	# Objets de tous les biomes : [pied, index du sprite, retourné].
	var prop_list := []

	for b in biomes.size():
		var biome := biomes[b]
		if biome.prop_density <= 0.0 or biome.props.is_empty():
			continue
		var ground_index := biomes.find(biome.ground_biome)

		# Masque (1 pixel par case, blanc = case de ce biome) et liste des cases où poser :
		# les cases du biome + celles de son sol à moins de PROP_SPILL_RADIUS cases.
		var mask := Image.create(map_size.x, map_size.y, false, Image.FORMAT_L8)
		var covered := {}
		for y in map_size.y:
			for x in map_size.x:
				if biome_map[y * map_size.x + x] != b:
					continue
				mask.set_pixel(x, y, Color.WHITE)
				for dy in range(-PROP_SPILL_RADIUS, PROP_SPILL_RADIUS + 1):
					for dx in range(-PROP_SPILL_RADIUS, PROP_SPILL_RADIUS + 1):
						var cx := x + dx
						var cy := y + dy
						if cx < 0 or cy < 0 or cx >= map_size.x or cy >= map_size.y:
							continue
						var nb := biome_map[cy * map_size.x + cx]
						if nb == b or nb == ground_index \
								or (biome.prop_spill_any and not biomes[nb] in foam_sea_biomes):
							covered[Vector2i(cx, cy)] = true
		_scatter_props(covered, _blurred(mask), biome, rng, prop_list)

	# Objets du sol : semés sur les seules cases du biome, avec leur propre densité et un
	# écart régulier (rochers sur le sol rocheux…).
	for b in biomes.size():
		var biome := biomes[b]
		if biome.ground_prop_density <= 0.0 or biome.ground_props.is_empty():
			continue
		var mask := Image.create(map_size.x, map_size.y, false, Image.FORMAT_L8)
		var cells := {}
		for y in map_size.y:
			for x in map_size.x:
				if biome_map[y * map_size.x + x] == b:
					mask.set_pixel(x, y, Color.WHITE)
					cells[Vector2i(x, y)] = true
		# Copie du biome dont les objets principaux sont remplacés par les objets du sol,
		# pour réutiliser _scatter_props.
		var ground_biome_props := biome.duplicate() as Biome
		ground_biome_props.props = biome.ground_props
		ground_biome_props.prop_density = biome.ground_prop_density
		ground_biome_props.prop_spacing = GROUND_PROP_SPACING
		_scatter_props(cells, _blurred(mask), ground_biome_props, rng, prop_list)

	# Contreforts : ceinture de petits objets autour des biomes qui en ont (montagnes…).
	for b in biomes.size():
		if biomes[b].fringe_density > 0.0 and not biomes[b].fringe_props.is_empty():
			_scatter_fringe(b, rng, prop_list)

	if props:
		props.set_props(prop_list)


# Pose la ceinture d'objets `fringe_props` du biome n° `b` sur les cases à moins de
# `fringe_radius` cases de lui : dense au bord du biome, de plus en plus rare en s'éloignant.
# Jamais dans l'eau (`foam_sea_biomes`) ni sur un biome qui a lui-même une ceinture (les
# montagnes et la neige ne reçoivent pas les buttes l'une de l'autre).
func _scatter_fringe(b: int, rng: RandomNumberGenerator, prop_list: Array) -> void:
	var biome := biomes[b]
	if props == null or props.regions.is_empty():
		return
	# Distance (en cases, diagonales comprises) au biome, calculée en partant de ses cases
	# et en s'étendant d'une case à chaque tour.
	var dist := {}
	var front: Array[Vector2i] = []
	for y in map_size.y:
		for x in map_size.x:
			if biome_map[y * map_size.x + x] == b:
				front.append(Vector2i(x, y))
	for d in range(1, biome.fringe_radius + 1):
		var next: Array[Vector2i] = []
		for cell in front:
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					var c := cell + Vector2i(dx, dy)
					if c.x < 0 or c.y < 0 or c.x >= map_size.x or c.y >= map_size.y or dist.has(c):
						continue
					var other := biomes[biome_map[c.y * map_size.x + c.x]]
					if other == biome or other in foam_sea_biomes or not other.fringe_props.is_empty():
						continue
					dist[c] = d
					next.append(c)
		front = next

	# Même tirage que _scatter_props, avec un écart minimal entre objets de la ceinture.
	var placed := {}
	var widest := 0
	for sprite in biome.fringe_props:
		widest = maxi(widest, props.regions[sprite].size.x)
	var reach := ceili(FRINGE_SPACING * widest / tile_size)
	for cell: Vector2i in dist:
		# 1 juste au bord, puis décroît jusqu'à 0 au-delà de fringe_radius.
		var falloff := 1.0 - float(dist[cell] - 1) / biome.fringe_radius
		var chance := biome.fringe_density * falloff / PROP_CANDIDATES_PER_CELL
		for c in PROP_CANDIDATES_PER_CELL:
			var spot := Vector2(cell) + Vector2(rng.randf(), rng.randf())
			if rng.randf() >= chance:
				continue
			var sprite: int = biome.fringe_props[rng.randi() % biome.fringe_props.size()]
			var foot := spot * tile_size
			var width := props.regions[sprite].size.x
			if not _prop_fits(foot, sprite) \
					or _too_close(placed, foot, width, FRINGE_SPACING, reach):
				continue
			var key := Vector2i(spot)
			if not placed.has(key):
				placed[key] = []
			placed[key].append([foot, width])
			prop_list.append([foot, sprite, rng.randf() < 0.5])


# Tire des emplacements d'objets dans les cases `covered` et les ajoute à `prop_list`.
# Chance d'avoir un objet : `biome.prop_density` par case au cœur du biome, de moins en
# moins vers le bord (selon le masque flou `mask`), jusqu'à zéro un peu au-delà.
# L'objet est choisi au hasard parmi `biome.props` qui tiennent dans la carte (voir
# _prop_fits). Si le biome a un `prop_spacing`,
# un objet tiré trop près d'un objet déjà posé est abandonné.
func _scatter_props(covered: Dictionary, mask: Image, biome: Biome,
		rng: RandomNumberGenerator, prop_list: Array) -> void:
	if props == null or props.regions.is_empty():
		return
	var chance := biome.prop_density / PROP_CANDIDATES_PER_CELL

	# Objets déjà posés, rangés par case : [pied, largeur]. Ainsi on ne compare un nouvel
	# objet qu'aux objets des cases voisines (à moins de `reach` cases), pas à tous.
	var placed := {}
	var reach := 0
	if biome.prop_spacing > 0.0:
		var widest := 0
		for sprite in biome.props:
			widest = maxi(widest, props.regions[sprite].size.x)
		reach = ceili(biome.prop_spacing * widest / tile_size)

	for cell: Vector2i in covered:
		for c in PROP_CANDIDATES_PER_CELL:
			# Position au hasard dans la case, en cases (ex. 12.4, 30.7).
			var spot := Vector2(cell) + Vector2(rng.randf(), rng.randf())
			var m := _mask_at(mask, spot)
			var p := chance * smoothstep(PROP_MASK_START, PROP_MASK_FULL, m)
			if rng.randf() < p:
				var pick := rng.randi()
				var foot := spot * tile_size
				# L'objet doit tenir entièrement dans la carte. Si celui tiré dépasse (gros
				# objet près du bord), on tire parmi ceux du biome qui tiennent à cet endroit.
				var sprite: int = biome.props[pick % biome.props.size()]
				if not _prop_fits(foot, sprite):
					var fitting: Array[int] = []
					for s in biome.props:
						if _prop_fits(foot, s):
							fitting.append(s)
					if fitting.is_empty():
						continue
					sprite = fitting[pick % fitting.size()]
				var width := props.regions[sprite].size.x
				if reach > 0:
					if _too_close(placed, foot, width, biome.prop_spacing, reach):
						continue
					var key := Vector2i(spot)
					if not placed.has(key):
						placed[key] = []
					placed[key].append([foot, width])
				prop_list.append([foot, sprite, rng.randf() < 0.5])


# Vrai si l'objet n° `sprite`, dont le pied (bas-centre du sprite, voir prop_scatter.gd) est
# posé sur `foot`, tient entièrement dans la carte.
func _prop_fits(foot: Vector2, sprite: int) -> bool:
	var size := Vector2(props.regions[sprite].size)
	var map_pixels := Vector2(map_size * tile_size)
	return foot.y - size.y >= 0.0 and foot.y <= map_pixels.y \
			and foot.x - size.x / 2.0 >= 0.0 and foot.x + size.x / 2.0 <= map_pixels.x


# Vrai si un objet de `placed` (voir _scatter_props) est trop près du pied `foot` :
# l'écart minimal entre deux pieds vaut `spacing` × la moyenne de leurs deux largeurs.
func _too_close(placed: Dictionary, foot: Vector2, width: int, spacing: float,
		reach: int) -> bool:
	var cell := Vector2i(foot / tile_size)
	for dy in range(-reach, reach + 1):
		for dx in range(-reach, reach + 1):
			for other in placed.get(cell + Vector2i(dx, dy), []):
				if foot.distance_to(other[0]) < spacing * (width + other[1]) / 2.0:
					return true
	return false


# Valeur du masque (1 pixel par case) à une position en cases, interpolée entre les centres
# des cases voisines : la densité d'objets varie ainsi en douceur au lieu de suivre les cases.
func _mask_at(mask: Image, spot: Vector2) -> float:
	var p := spot - Vector2(0.5, 0.5)
	var x0 := clampi(floori(p.x), 0, map_size.x - 1)
	var y0 := clampi(floori(p.y), 0, map_size.y - 1)
	var x1 := mini(x0 + 1, map_size.x - 1)
	var y1 := mini(y0 + 1, map_size.y - 1)
	var fx := clampf(p.x - x0, 0.0, 1.0)
	var fy := clampf(p.y - y0, 0.0, 1.0)
	var top := lerpf(mask.get_pixel(x0, y0).r, mask.get_pixel(x1, y0).r, fx)
	var bottom := lerpf(mask.get_pixel(x0, y1).r, mask.get_pixel(x1, y1).r, fx)
	return lerpf(top, bottom, fy)


# Floute un masque en moyennant chaque pixel avec ses 8 voisins : la frontière devient
# une pente douce sur ~1 case.
func _blurred(image: Image) -> Image:
	var out := Image.create(image.get_width(), image.get_height(), false, Image.FORMAT_L8)
	for y in image.get_height():
		for x in image.get_width():
			var sum := 0.0
			var count := 0
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					var cx := x + dx
					var cy := y + dy
					if cx < 0 or cy < 0 or cx >= image.get_width() or cy >= image.get_height():
						continue
					sum += image.get_pixel(cx, cy).r
					count += 1
			var v := sum / count
			out.set_pixel(x, y, Color(v, v, v))
	return out


## Biome de la case `cell`, ou null en dehors de la carte.
# func get_biome_at(cell: Vector2i) -> Biome:
# 	if cell.x < 0 or cell.y < 0 or cell.x >= map_size.x or cell.y >= map_size.y:
# 		return null
# 	return biomes[biome_map[cell.y * map_size.x + cell.x]]


# static func default_biomes() -> Array[Biome]:
# 	return [
# 		Biome.make("Eau profonde", Color(0.10, 0.20, 0.50), 0.30),
# 		Biome.make("Eau", Color(0.18, 0.38, 0.75), 0.40),
# 		Biome.make("Sable", Color(0.87, 0.80, 0.55), 0.44),
# 		Biome.make("Marais", Color(0.30, 0.40, 0.28), 0.60, 0.65),
# 		Biome.make("Désert", Color(0.85, 0.70, 0.40), 0.60, 0.0, 0.30),
# 		Biome.make("Plaine", Color(0.45, 0.72, 0.30), 0.60),
# 		Biome.make("Forêt", Color(0.16, 0.45, 0.20), 0.75, 0.45),
# 		Biome.make("Collines", Color(0.55, 0.60, 0.30), 0.75),
# 		Biome.make("Montagne", Color(0.50, 0.47, 0.45), 0.88),
# 		Biome.make("Neige", Color(0.95, 0.95, 0.97), 1.01),
# 	]


# Crée un générateur de bruit de Perlin « fractal » (plusieurs couches de détails).
func _make_noise(noise_seed: int, frequency: float, octaves: int,
		lacunarity: float, gain: float) -> FastNoiseLite:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_PERLIN
	noise.seed = noise_seed
	noise.frequency = frequency
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = octaves
	noise.fractal_lacunarity = lacunarity
	noise.fractal_gain = gain
	return noise


# Lit la valeur du bruit pour chaque case de la carte (valeurs brutes, environ -1..1).
func _sample(noise: FastNoiseLite) -> PackedFloat32Array:
	var values := PackedFloat32Array()
	values.resize(map_size.x * map_size.y)
	for y in map_size.y:
		for x in map_size.x:
			values[y * map_size.x + x] = noise.get_noise_2d(x, y)
	return values


## Ramène les valeurs sur 0..1 : les seuils des biomes restent stables quel que soit le seed.
## (la plus petite valeur devient 0, la plus grande devient 1)
func _normalized(values: PackedFloat32Array) -> PackedFloat32Array:
	var lo := INF
	var hi := -INF
	for v in values:
		lo = minf(lo, v)
		hi = maxf(hi, v)
	var span := maxf(hi - lo, MIN_NOISE_SPAN)
	for i in values.size():
		values[i] = (values[i] - lo) / span
	return values


# Mode île : abaisse l'élévation près des bords pour qu'ils passent sous l'eau.
func _apply_island_falloff() -> void:
	for y in map_size.y:
		for x in map_size.x:
			# d = distance au centre de la carte (0 au centre, ~1 sur les bords, ~1.4 aux coins).
			var d := Vector2(float(x) / map_size.x * 2.0 - 1.0,
					float(y) / map_size.y * 2.0 - 1.0).length()
			# Masque radial : centre intact, bords progressivement enfoncés sous l'eau.
			var mask := 1.0 - island_falloff * smoothstep(ISLAND_FALLOFF_START, ISLAND_FALLOFF_END, d)
			var i := y * map_size.x + x
			height_map[i] *= mask


# Renvoie l'index du premier biome dont les seuils correspondent à la case.
# Si aucun ne correspond, prend le dernier de la liste.
func _pick_biome(height: float, moisture: float) -> int:
	for i in biomes.size():
		if biomes[i].matches(height, moisture):
			return i
	return biomes.size() - 1


## Ajoute à la TileSet de `ground` une source de tuiles de couleur unie (une par biome).
## Elle sert aux biomes sans texture (atlas_coords = (-1, -1)).
func _ensure_tileset() -> void:
	var tile_set := ground.tile_set
	if tile_set == null:
		tile_set = TileSet.new()
		tile_set.tile_size = Vector2i(tile_size, tile_size)
	# Copie de travail : la source de couleurs n'est pas ajoutée à la ressource .tres partagée.
	if not tile_set.get_meta("runtime_copy", false):
		tile_set = tile_set.duplicate()
		tile_set.set_meta("runtime_copy", true)
	ground.tile_set = tile_set
	# On retire l'ancienne source de couleurs (les couleurs des biomes ont pu changer).
	if tile_set.has_source(COLOR_SOURCE_ID):
		tile_set.remove_source(COLOR_SOURCE_ID)

	# Image d'une ligne de carrés : un carré de la couleur de chaque biome, côte à côte.
	var count := biomes.size()
	var image := Image.create(tile_size * count, tile_size, false, Image.FORMAT_RGBA8)
	for i in count:
		var color := biomes[i].color
		image.fill_rect(Rect2i(i * tile_size, 0, tile_size, tile_size), color)

	# On découpe cette image en tuiles : la tuile (i, 0) = couleur du biome n° i.
	var source := TileSetAtlasSource.new()
	source.texture = ImageTexture.create_from_image(image)
	source.texture_region_size = Vector2i(tile_size, tile_size)
	for i in count:
		source.create_tile(Vector2i(i, 0))

	tile_set.add_source(source, COLOR_SOURCE_ID)


# Met à jour le texte d'aide en haut de l'écran.
func _update_info() -> void:
	if info_label == null:
		return
	info_label.text = "Seed : %d   |   Île : %s   |   Effets : %s\n[R] nouvelle carte   [I] mode île   [E] effets   [ZQSD / flèches] déplacer   [molette] zoom   [clic droit] glisser" % [
		world_seed, "oui" if island_mode else "non", "oui" if effects_enabled else "non"]
