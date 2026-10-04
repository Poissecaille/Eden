@tool
class_name Biome
extends Resource
## Un biome = une plage d'élévation et d'humidité (valeurs normalisées 0..1).
## Les biomes sont testés dans l'ordre du tableau : le premier qui correspond gagne.
##
## Exemple : Plaine a max_height = 0.6 -> toute case sous 0.6 d'élévation qui n'a pas
## déjà été prise par un biome placé avant (eau, sable, marais, désert) devient Plaine.

# Nom affiché (pour s'y retrouver dans l'inspecteur).
@export var name := ""
## Couleur unie utilisée quand le biome n'a pas de texture (atlas_coords = (-1, -1)).
@export var color := Color.WHITE

# --- Conditions pour qu'une case appartienne à ce biome ---
# Élévation strictement inférieure à cette valeur.
@export_range(0.0, 1.01) var max_height := 1.01
# Humidité comprise entre min_moisture (inclus) et max_moisture (exclu).
@export_range(0.0, 1.01) var min_moisture := 0.0
@export_range(0.0, 1.01) var max_moisture := 1.01

# --- Distance à garder avec d'autres biomes ---
## Biomes que ce biome ne doit jamais toucher (ex. le marais et l'eau). Ses cases trop
## proches prennent le biome suivant qui correspond à leur élévation et leur humidité.
@export var keep_away_from: Array[Biome] = []
## Nombre minimal de cases entre ce biome et ceux de `keep_away_from`.
@export_range(1, 6) var keep_away_distance := 2

# --- Texture dans un atlas de la TileSet (terrain_tileset.tres) ---
# Source 0 = grass_atlas.png : chaque texture occupe un bloc de 5 x 3 tuiles de 64 px ;
#            la texture de la colonne c et de la ligne r de sources/grass_sheet.jpg
#            commence en (5·c, 3·r).
# Source 1 = desert_atlas.png : même disposition, à partir de sources/desert_sheet.jpg, mais
#            chaque texture n'occupe que 5 x 2 tuiles (pattern_size = (5, 2)) en haut de son bloc.
# Source 2 = swamp_atlas.png : même disposition que la source 1, à partir de sources/swamp_sheet.jpg.
# Source 3 = water_atlas.png : même disposition que la source 1, à partir de sources/water_sheet.jpg.
# Source 4 = rocky_atlas.png : 4 blocs de 10 x 6 tuiles (pattern_size = (10, 6)) assemblés à partir
#            de sources/rocky_sheet.jpg ; base (0, 0), variantes (10, 0), (0, 6), (10, 6).
## Id de la source d'atlas (l'image) dans la TileSet où se trouve la texture du biome.
@export var source_id := 0
## Coin haut-gauche du bloc de texture dans l'atlas ; (-1, -1) = pas de texture, couleur unie.
@export var atlas_coords := Vector2i(-1, -1)
## Taille (en tuiles) du bloc de texture qui commence à `atlas_coords` et se répète sur la carte.
@export var pattern_size := Vector2i(1, 1)
## Blocs de texture supplémentaires (coin haut-gauche, même `pattern_size`), répartis par plaques.
@export var extra_variants: Array[Vector2i] = []

# --- Sol emprunté à un autre biome ---
## Si renseigné, le sol de ce biome est peint avec la texture de ce biome-là
## (ex. la forêt a pour sol la Plaine : herbe sous les arbres). Ses propres texture et
## couleur sont alors ignorées.
@export var ground_biome: Biome

# --- Objets du décor (sprites posés par-dessus, voir prop_scatter.gd) ---
## Numéros des objets utilisables par ce biome dans PropScatter.regions
## (props_atlas.png : 0-14 = arbres, 15-25 = buttes, 26-30 = touffes, 31-34 = rochers,
## 35-37 = montagnes, 38-40 = montagnes enneigées, 41-50 = quenouilles du marais). Un numéro répété est tiré plus souvent.
@export var props: Array[int] = []
## Nombre moyen d'objets par case au cœur du biome (0 = aucun). La densité baisse près du
## bord, et quelques objets débordent sur les cases voisines de son `ground_biome`.
@export_range(0.0, 4.0) var prop_density := 0.0
## Écart minimal entre les pieds de deux objets de ce biome, en fraction de leur largeur
## (0 = aucun écart imposé, 1 = côte à côte, 0.7 = ils se chevauchent d'environ 30 %).
## Évite que de gros objets s'empilent en paquets ; `prop_density` devient alors un maximum.
@export_range(0.0, 1.5) var prop_spacing := 0.0
## Si coché, quelques objets débordent aussi sur les biomes voisins (sauf l'eau), et pas
## seulement sur `ground_biome` : utile pour les montagnes, qui ont leur propre sol rocheux
## mais doivent recouvrir son pourtour.
@export var prop_spill_any := false

# --- Objets du sol : petits objets semés sur les cases du biome, indépendamment des objets
# principaux (ex. rochers sur le sol rocheux, entre les montagnes) ---
## Numéros des objets du sol (vide = aucun).
@export var ground_props: Array[int] = []
## Nombre moyen d'objets du sol par case.
@export_range(0.0, 2.0) var ground_prop_density := 0.0

# --- Contreforts : petits objets posés en ceinture autour du biome (ex. buttes et rochers
# au pied des montagnes), pour qu'il ne repose pas brutalement sur ses voisins ---
## Numéros des objets de la ceinture (vide = pas de ceinture).
@export var fringe_props: Array[int] = []
## Nombre moyen d'objets par case juste au bord du biome ; la densité baisse jusqu'à zéro
## à `fringe_radius` cases.
@export_range(0.0, 2.0) var fringe_density := 0.0
## Largeur de la ceinture, en cases.
@export_range(1, 6) var fringe_radius := 3
## Biomes où la ceinture n'est jamais posée (ex. pas de buttes entre les arbres de la forêt).
@export var fringe_excluded: Array[Biome] = []


# Vrai si une case avec cette élévation et cette humidité appartient à ce biome.
func matches(height: float, moisture: float) -> bool:
	return height < max_height and moisture >= min_moisture and moisture < max_moisture


# static func make(biome_name: String, biome_color: Color, height_max: float,
# 		moisture_min := 0.0, moisture_max := 1.01) -> Biome:
# 	var biome := Biome.new()
# 	biome.name = biome_name
# 	biome.color = biome_color
# 	biome.max_height = height_max
# 	biome.min_moisture = moisture_min
# 	biome.max_moisture = moisture_max
# 	return biome
