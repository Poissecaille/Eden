@tool
class_name WorldGenerator
extends Node2D
## Génère une carte de tuiles 2D à partir de deux bruits de Perlin :
## l'élévation (eau -> plaine -> montagne -> neige) et l'humidité (désert <-> marais/forêt).

signal generated

@export var ground: TileMapLayer
@export var info_label: Label

@export var map_size := Vector2i(200, 120)
@export var tile_size := 16
@export var world_seed := 0
@export var randomize_seed_on_start := true

@export_group("Élévation")
@export var height_frequency := 0.025
@export_range(1, 8) var height_octaves := 5
@export var height_lacunarity := 2.0
@export_range(0.0, 1.0) var height_gain := 0.5

@export_group("Humidité")
@export var moisture_frequency := 0.015
@export_range(1, 8) var moisture_octaves := 3

@export_group("Forme")
## Abaisse les bords de la carte pour obtenir une île entourée d'eau.
@export var island_mode := false
@export_range(0.0, 1.0) var island_falloff := 0.7

@export_group("Tuiles")
## Laisse vide pour utiliser les biomes par défaut.
@export var biomes: Array[Biome] = []
## Id de la source atlas dans la TileSet de `ground`.
@export var source_id := 0

@export_group("Éditeur")
## Coche pour générer un aperçu directement dans l'éditeur.
@export var generate_now := false:
	set(value):
		if value and is_node_ready():
			generate()
@export var clear_now := false:
	set(value):
		if value and ground:
			ground.clear()

var height_map := PackedFloat32Array()
var moisture_map := PackedFloat32Array()
## Index du biome de chaque case (y * map_size.x + x), pratique pour le gameplay.
var biome_map := PackedInt32Array()


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	if randomize_seed_on_start:
		world_seed = randi() % 1_000_000
	generate()


func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_R:
				world_seed = randi() % 1_000_000
				generate()
			KEY_I:
				island_mode = not island_mode
				generate()


func generate() -> void:
	if ground == null:
		push_error("WorldGenerator : aucun TileMapLayer assigné à 'ground'.")
		return
	if biomes.is_empty():
		biomes = default_biomes()
	var placeholder := _ensure_tileset()

	height_map = _normalized(_sample(_make_noise(world_seed, height_frequency,
			height_octaves, height_lacunarity, height_gain)))
	moisture_map = _normalized(_sample(_make_noise(world_seed + 1, moisture_frequency,
			moisture_octaves, 2.0, 0.5)))
	if island_mode:
		_apply_island_falloff()

	ground.clear()
	biome_map.resize(map_size.x * map_size.y)
	for y in map_size.y:
		for x in map_size.x:
			var i := y * map_size.x + x
			var b := _pick_biome(height_map[i], moisture_map[i])
			biome_map[i] = b
			var coords := Vector2i(b, 0) if placeholder else biomes[b].atlas_coords
			ground.set_cell(Vector2i(x, y), source_id, coords)

	_update_info()
	generated.emit()


## Biome de la case `cell`, ou null en dehors de la carte.
func get_biome_at(cell: Vector2i) -> Biome:
	if cell.x < 0 or cell.y < 0 or cell.x >= map_size.x or cell.y >= map_size.y:
		return null
	return biomes[biome_map[cell.y * map_size.x + cell.x]]


static func default_biomes() -> Array[Biome]:
	return [
		Biome.make("Eau profonde", Color(0.10, 0.20, 0.50), 0.30),
		Biome.make("Eau", Color(0.18, 0.38, 0.75), 0.40),
		Biome.make("Sable", Color(0.87, 0.80, 0.55), 0.44),
		Biome.make("Marais", Color(0.30, 0.40, 0.28), 0.60, 0.65),
		Biome.make("Désert", Color(0.85, 0.70, 0.40), 0.60, 0.0, 0.30),
		Biome.make("Plaine", Color(0.45, 0.72, 0.30), 0.60),
		Biome.make("Forêt", Color(0.16, 0.45, 0.20), 0.75, 0.45),
		Biome.make("Collines", Color(0.55, 0.60, 0.30), 0.75),
		Biome.make("Montagne", Color(0.50, 0.47, 0.45), 0.88),
		Biome.make("Neige", Color(0.95, 0.95, 0.97), 1.01),
	]


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


func _sample(noise: FastNoiseLite) -> PackedFloat32Array:
	var values := PackedFloat32Array()
	values.resize(map_size.x * map_size.y)
	for y in map_size.y:
		for x in map_size.x:
			values[y * map_size.x + x] = noise.get_noise_2d(x, y)
	return values


## Ramène les valeurs sur 0..1 : les seuils des biomes restent stables quel que soit le seed.
func _normalized(values: PackedFloat32Array) -> PackedFloat32Array:
	var lo := INF
	var hi := -INF
	for v in values:
		lo = minf(lo, v)
		hi = maxf(hi, v)
	var span := maxf(hi - lo, 0.0001)
	for i in values.size():
		values[i] = (values[i] - lo) / span
	return values


func _apply_island_falloff() -> void:
	for y in map_size.y:
		for x in map_size.x:
			var d := Vector2(float(x) / map_size.x * 2.0 - 1.0,
					float(y) / map_size.y * 2.0 - 1.0).length()
			# Masque radial : centre intact, bords progressivement enfoncés sous l'eau.
			var mask := 1.0 - island_falloff * smoothstep(0.5, 1.2, d)
			var i := y * map_size.x + x
			height_map[i] *= mask


func _pick_biome(height: float, moisture: float) -> int:
	for i in biomes.size():
		if biomes[i].matches(height, moisture):
			return i
	return biomes.size() - 1


## Crée une TileSet placeholder (un carré de couleur par biome) si aucune vraie TileSet
## n'est assignée. Renvoie true si on est en mode placeholder.
func _ensure_tileset() -> bool:
	var current := ground.tile_set
	if current != null and not current.get_meta("placeholder", false):
		return false

	var count := biomes.size()
	var image := Image.create(tile_size * count, tile_size, false, Image.FORMAT_RGBA8)
	for i in count:
		var color := biomes[i].color
		image.fill_rect(Rect2i(i * tile_size, 0, tile_size, tile_size), color.darkened(0.12))
		image.fill_rect(Rect2i(i * tile_size + 1, 1, tile_size - 2, tile_size - 2), color)

	var source := TileSetAtlasSource.new()
	source.texture = ImageTexture.create_from_image(image)
	source.texture_region_size = Vector2i(tile_size, tile_size)
	for i in count:
		source.create_tile(Vector2i(i, 0))

	var tile_set := TileSet.new()
	tile_set.tile_size = Vector2i(tile_size, tile_size)
	tile_set.add_source(source, source_id)
	tile_set.set_meta("placeholder", true)
	ground.tile_set = tile_set
	return true


func _update_info() -> void:
	if info_label == null:
		return
	info_label.text = "Seed : %d   |   Île : %s\n[R] nouvelle carte   [I] mode île   [ZQSD / flèches] déplacer   [molette] zoom   [clic droit] glisser" % [
		world_seed, "oui" if island_mode else "non"]
