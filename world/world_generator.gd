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
##   5. les biomes qui ont des arbres (ex. forêt) reçoivent des sprites d'arbres par-dessus,
##      de plus en plus clairsemés vers leur bord.

# Émis à la fin de chaque génération (la caméra l'écoute pour se recadrer).
signal generated

## Id de la source (générée au lancement) des tuiles de couleur unie.
const COLOR_SOURCE_ID := 100
# Shader qui rend les couches de variantes visibles seulement par taches.
const VARIANT_SHADER := preload("res://world/shaders/variant_blend.gdshader")

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
# Nombre de cases autour d'un biome à arbres où quelques arbres peuvent déborder sur son sol.
const TREE_SPILL_RADIUS := 2
# Emplacements tirés au hasard par case pour les arbres (chacun reçoit un arbre ou non).
const TREE_CANDIDATES_PER_CELL := 3
# Valeur du masque flou (0 = hors du biome, 1 = en plein cœur) où les arbres commencent
# à apparaître / atteignent leur pleine densité : de rares arbres débordent sur le bord.
const TREE_MASK_START := 0.3
const TREE_MASK_FULL := 0.8

# ---------------------------------------------------------------------------
# Réglages (visibles dans l'inspecteur du nœud World)
# ---------------------------------------------------------------------------

# Couche de tuiles principale sur laquelle on dessine la carte.
@export var ground: TileMapLayer
# Texte d'aide affiché en haut de l'écran (seed + touches).
@export var info_label: Label
# Nœud qui dessine les arbres (sprites) par-dessus les tuiles.
@export var trees: TreeScatter

# Taille de la carte, en nombre de cases.
@export var map_size := Vector2i(200, 120)
# Taille d'une case en pixels : doit être la même que celle de la TileSet (64 actuellement).
@export var tile_size := 16
# Graine du hasard : même graine = même carte.
@export var world_seed := 0
# Si coché, une graine aléatoire est tirée à chaque lancement du jeu.
@export var randomize_seed_on_start := true

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


# Au lancement du jeu : tire une graine si demandé, puis génère la carte.
# Dans l'éditeur on ne fait rien (il faut cocher `generate_now`).
func _ready() -> void:
	if Engine.is_editor_hint():
		return
	if randomize_seed_on_start:
		world_seed = randi() % MAX_SEED
	generate()


# Touches du jeu : R = nouvelle carte, I = active/désactive le mode île.
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

	# --- Étape 5 : les arbres, posés par-dessus ---
	_place_trees()

	_update_info()
	generated.emit()


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


## Pose les arbres de chaque biome qui a une `tree_density` : sur ses propres cases, et
## quelques-uns sur les cases de son `ground_biome` à moins de TREE_SPILL_RADIUS cases.
func _place_trees() -> void:
	# Tirages déterminés par la graine (graine différente de celle des variantes).
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed + 1
	# Arbres de tous les biomes : [pied, index du sprite, retourné].
	var tree_list := []

	for b in biomes.size():
		var biome := biomes[b]
		if biome.tree_density <= 0.0:
			continue
		var ground_index := biomes.find(biome.ground_biome)

		# Masque (1 pixel par case, blanc = case de ce biome) et liste des cases où poser :
		# les cases du biome + celles de son sol à moins de TREE_SPILL_RADIUS cases.
		var mask := Image.create(map_size.x, map_size.y, false, Image.FORMAT_L8)
		var covered := {}
		for y in map_size.y:
			for x in map_size.x:
				if biome_map[y * map_size.x + x] != b:
					continue
				mask.set_pixel(x, y, Color.WHITE)
				for dy in range(-TREE_SPILL_RADIUS, TREE_SPILL_RADIUS + 1):
					for dx in range(-TREE_SPILL_RADIUS, TREE_SPILL_RADIUS + 1):
						var cx := x + dx
						var cy := y + dy
						if cx < 0 or cy < 0 or cx >= map_size.x or cy >= map_size.y:
							continue
						var nb := biome_map[cy * map_size.x + cx]
						if nb == b or nb == ground_index:
							covered[Vector2i(cx, cy)] = true
		_scatter_trees(covered, _blurred(mask), biome.tree_density, rng, tree_list)

	if trees:
		trees.set_trees(tree_list)


# Tire des emplacements d'arbres dans les cases `covered` et les ajoute à `tree_list`.
# Chance d'avoir un arbre : `density` par case au cœur du biome, de moins en moins vers la
# bord (selon le masque flou `mask`), jusqu'à zéro un peu au-delà.
func _scatter_trees(covered: Dictionary, mask: Image, density: float,
		rng: RandomNumberGenerator, tree_list: Array) -> void:
	if trees == null or trees.regions.is_empty():
		return
	var chance := density / TREE_CANDIDATES_PER_CELL
	for cell: Vector2i in covered:
		for c in TREE_CANDIDATES_PER_CELL:
			# Position au hasard dans la case, en cases (ex. 12.4, 30.7).
			var spot := Vector2(cell) + Vector2(rng.randf(), rng.randf())
			var m := _mask_at(mask, spot)
			var p := chance * smoothstep(TREE_MASK_START, TREE_MASK_FULL, m)
			if rng.randf() < p:
				tree_list.append([spot * tile_size, rng.randi() % trees.regions.size(),
						rng.randf() < 0.5])


# Valeur du masque (1 pixel par case) à une position en cases, interpolée entre les centres
# des cases voisines : la densité d'arbres varie ainsi en douceur au lieu de suivre les cases.
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
	info_label.text = "Seed : %d   |   Île : %s\n[R] nouvelle carte   [I] mode île   [ZQSD / flèches] déplacer   [molette] zoom   [clic droit] glisser" % [
		world_seed, "oui" if island_mode else "non"]
