extends Area2D

@export var click_size: Vector2 = Vector2(96, 80)
@export var footprint_tiles: Vector2i = Vector2i(6, 5)

const SELECTION_RING_SCRIPT = preload("res://scripts/selection_ring.gd")
const DEPTH_SORT_OFFSET := 2048

var hover_mode: bool = false
var select_mode: bool = false
var selection_ring

func _ready():
	add_to_group("ResourceDropoff")
	z_index = clampi(int(global_position.y) + DEPTH_SORT_OFFSET, 0, 4096)
	_create_selection_ring()
	queue_redraw()

func get_footprint_tiles() -> Vector2i:
	return footprint_tiles

func get_rect() -> Rect2:
	return Rect2(global_position - click_size * 0.5, click_size)

func set_hover(is_hover: bool):
	if hover_mode == is_hover:
		return
	hover_mode = is_hover
	_update_selection_ring()

func select():
	select_mode = true
	_update_selection_ring()

func deselect():
	select_mode = false
	_update_selection_ring()

func _create_selection_ring():
	selection_ring = Node2D.new()
	selection_ring.set_script(SELECTION_RING_SCRIPT)
	var visual_size = _get_visual_size()
	selection_ring.radius = visual_size.x / 2.0 * 0.95
	selection_ring.offset = Vector2(0, -3)
	selection_ring.hover_color = Color(1.0, 0.95, 0.0, 1.0)
	selection_ring.selected_color = Color(0.0, 1.0, 0.0, 0.9)
	selection_ring.visible = false
	add_child(selection_ring)

func _get_visual_size() -> Vector2:
	var sprite = get_node_or_null("Sprite2D")
	if sprite and sprite is Sprite2D and sprite.texture:
		return sprite.texture.get_size() * sprite.scale
	return click_size

func _update_selection_ring():
	if selection_ring:
		selection_ring.set_modes(hover_mode, select_mode)

func _draw():
	draw_rect(Rect2(-48, -40, 96, 80), Color(0.18, 0.18, 0.2, 0.85), true)
	draw_rect(Rect2(-48, -40, 96, 80), Color(0.65, 0.75, 0.8), false, 2.0)
	draw_rect(Rect2(-28, -12, 56, 36), Color(0.1, 0.12, 0.15), true)
	draw_rect(Rect2(-28, -12, 56, 36), Color(0.65, 0.75, 0.8), false, 1.0)
