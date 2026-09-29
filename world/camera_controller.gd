extends Camera2D
## Caméra d'exploration : ZQSD/WASD ou flèches pour se déplacer, molette pour zoomer,
## clic droit / clic molette maintenu pour glisser. Se recadre après chaque génération.

@export var world: WorldGenerator
@export var pan_speed := 800.0
@export var zoom_step := 1.15
@export var min_zoom := 0.1
@export var max_zoom := 8.0

var _dragging := false


func _ready() -> void:
	if world:
		world.generated.connect(_fit_to_map)


func _process(delta: float) -> void:
	# Touches physiques : la position W/A/S/D correspond à Z/Q/S/D sur un clavier AZERTY.
	var dir := Vector2(
		_axis(KEY_A, KEY_LEFT, KEY_D, KEY_RIGHT),
		_axis(KEY_W, KEY_UP, KEY_S, KEY_DOWN))
	position += dir.normalized() * pan_speed * delta / zoom.x


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


func _axis(neg_key: Key, neg_alt: Key, pos_key: Key, pos_alt: Key) -> float:
	var neg := Input.is_physical_key_pressed(neg_key) or Input.is_key_pressed(neg_alt)
	var pos := Input.is_physical_key_pressed(pos_key) or Input.is_key_pressed(pos_alt)
	return float(pos) - float(neg)


func _zoom_by(factor: float) -> void:
	var z := clampf(zoom.x * factor, min_zoom, max_zoom)
	zoom = Vector2(z, z)


func _fit_to_map() -> void:
	var size := Vector2(world.map_size * world.tile_size)
	position = size / 2.0
	var viewport := get_viewport_rect().size
	var z := minf(viewport.x / size.x, viewport.y / size.y) * 0.95
	zoom = Vector2(z, z)
