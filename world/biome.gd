@tool
class_name Biome
extends Resource
## Un biome = une plage d'élévation et d'humidité (valeurs normalisées 0..1).
## Les biomes sont testés dans l'ordre du tableau : le premier qui correspond gagne.

@export var name := ""
## Couleur de la tuile placeholder (utilisée tant qu'aucune vraie TileSet n'est assignée).
@export var color := Color.WHITE
@export_range(0.0, 1.01) var max_height := 1.01
@export_range(0.0, 1.01) var min_moisture := 0.0
@export_range(0.0, 1.01) var max_moisture := 1.01
## Coordonnées de la tuile dans l'atlas de ta vraie TileSet. Ignoré en mode placeholder.
@export var atlas_coords := Vector2i(-1, -1)


func matches(height: float, moisture: float) -> bool:
	return height < max_height and moisture >= min_moisture and moisture < max_moisture


static func make(biome_name: String, biome_color: Color, height_max: float,
		moisture_min := 0.0, moisture_max := 1.01) -> Biome:
	var biome := Biome.new()
	biome.name = biome_name
	biome.color = biome_color
	biome.max_height = height_max
	biome.min_moisture = moisture_min
	biome.max_moisture = moisture_max
	return biome
