extends Area2D

@export var footprint_tiles: Vector2i = Vector2i(7, 5)
@export var tile_size: int = 16
@export var display_name: String = "유적지"
@export var description: String = "발굴지를 건설하면 유물을 채취할 수 있다"
@export var resource_amount: int = 1000
@export var max_resource_amount: int = 0
@export var icon_texture: Texture2D = preload("res://캐릭터 폴더/map/historic site.png")

const SELECTION_RING_SCRIPT = preload("res://scripts/selection_ring.gd")
const RUINS_TEXTURE = preload("res://캐릭터 폴더/map/historic site.png")
const DEPTH_SORT_OFFSET := 2048

var used := false
var hover_mode := false
var select_mode := false
var selection_ring

func _ready():
	add_to_group("Ruins")
	if max_resource_amount <= 0:
		max_resource_amount = resource_amount
	input_pickable = true
	z_index = clampi(int(global_position.y) + DEPTH_SORT_OFFSET, 0, 4096)
	_create_selection_ring()
	queue_redraw()

func get_footprint_tiles() -> Vector2i:
	return footprint_tiles

func get_rect() -> Rect2:
	var size = Vector2(footprint_tiles * tile_size)
	return Rect2(global_position - size * 0.5, size)

func set_used(is_used: bool):
	used = is_used
	visible = not used and resource_amount > 0
	input_pickable = visible
	if used:
		set_hover(false)
		deselect()
	queue_redraw()

func consume_resource(amount: int) -> int:
	if resource_amount <= 0:
		return 0
	var mined = min(amount, resource_amount)
	resource_amount -= mined
	if resource_amount <= 0:
		_clear_placement_obstacle()
		set_used(true)
	queue_redraw()
	_refresh_selection_info_if_selected()
	return mined

func is_depleted() -> bool:
	return resource_amount <= 0

func get_max_resource_amount() -> int:
	return max_resource_amount

func _clear_placement_obstacle():
	var placement = get_tree().get_first_node_in_group("BuildingPlacement")
	if placement and placement.has_method("clear_node_obstacle"):
		placement.clear_node_obstacle(self)

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

func set_selected(value: bool):
	if value:
		select()
	else:
		deselect()

func _refresh_selection_info_if_selected():
	if not select_mode:
		return
	var manager = get_tree().get_first_node_in_group("UnitManager")
	if manager and manager.has_method("_refresh_command_ui"):
		manager._refresh_command_ui()

func _create_selection_ring():
	selection_ring = Node2D.new()
	selection_ring.set_script(SELECTION_RING_SCRIPT)
	var size = Vector2(footprint_tiles * tile_size)
	selection_ring.radius = size.x * 0.68
	selection_ring.ellipse_scale = Vector2(1.0, max(0.3, size.y / max(size.x, 1.0) * 0.5))
	selection_ring.offset = Vector2(0, size.y * 0.24)
	selection_ring.hover_color = Color(1.0, 0.95, 0.0, 1.0)
	selection_ring.selected_color = Color(1.0, 0.95, 0.0, 1.0)
	selection_ring.visible = false
	add_child(selection_ring)

func _update_selection_ring():
	if selection_ring:
		selection_ring.set_modes(hover_mode, select_mode)

func _draw():
	var size = Vector2(footprint_tiles * tile_size)
	var rect = Rect2(-size * 0.5, size)
	draw_texture_rect(RUINS_TEXTURE, rect, false)
