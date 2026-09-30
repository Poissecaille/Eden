extends Camera2D
## Caméra d'exploration : ZQSD/WASD ou flèches pour se déplacer, molette pour zoomer,
## clic droit / clic molette maintenu pour glisser. Se recadre après chaque génération.

# Générateur de carte à suivre (pour se recadrer quand une nouvelle carte est générée).
@export var world: WorldGenerator
# Vitesse de déplacement au clavier, en pixels par seconde (à zoom 1).
@export var pan_speed := 800.0
# Multiplicateur de zoom à chaque cran de molette.
@export var zoom_step := 1.15
# Zoom minimum (vue de loin) et maximum (vue de près).
@export var min_zoom := 0.1
@export var max_zoom := 8.0

# Part de l'écran occupée par la carte après recadrage (0.95 = petite marge autour).
const FIT_MARGIN := 0.95

# Vrai tant que le clic droit (ou molette) est maintenu : la souris fait glisser la vue.
var _dragging := false


# Se branche sur le signal `generated` du générateur pour recadrer après chaque carte.
func _ready() -> void:
	if world:
		world.generated.connect(_fit_to_map)


# Déplacement au clavier, à chaque image.
func _process(delta: float) -> void:
	# Touches physiques : la position W/A/S/D correspond à Z/Q/S/D sur un clavier AZERTY.
	var dir := Vector2(
		_axis(KEY_A, KEY_LEFT, KEY_D, KEY_RIGHT),
		_axis(KEY_W, KEY_UP, KEY_S, KEY_DOWN))
	# Divisé par le zoom : on se déplace à la même vitesse à l'écran, quel que soit le zoom.
	position += dir.normalized() * pan_speed * delta / zoom.x


# Souris : molette = zoom, clic droit/molette maintenu + mouvement = glisser la vue.
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				if event.pressed:
					_zoom_by(zoom_step)
			MOUSE_BUTTON_WHEEL_DOWN:
				if event.pressed:
					_zoom_by(1.0 / zoom_step)
			MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE:
				_dragging = event.pressed
	elif event is InputEventMouseMotion and _dragging:
		position -= event.relative / zoom


# Renvoie -1, 0 ou 1 selon la touche enfoncée sur un axe (négative / aucune / positive).
func _axis(neg_key: Key, neg_alt: Key, pos_key: Key, pos_alt: Key) -> float:
	var neg := Input.is_physical_key_pressed(neg_key) or Input.is_key_pressed(neg_alt)
	var pos := Input.is_physical_key_pressed(pos_key) or Input.is_key_pressed(pos_alt)
	return float(pos) - float(neg)


# Multiplie le zoom par `factor`, en restant entre min_zoom et max_zoom.
func _zoom_by(factor: float) -> void:
	var z := clampf(zoom.x * factor, min_zoom, max_zoom)
	zoom = Vector2(z, z)


# Centre la caméra sur la carte et règle le zoom pour qu'elle tienne entière à l'écran.
func _fit_to_map() -> void:
	var size := Vector2(world.map_size * world.tile_size)
	position = size / 2.0
	var viewport := get_viewport_rect().size
	var z := minf(viewport.x / size.x, viewport.y / size.y) * FIT_MARGIN
	zoom = Vector2(z, z)
