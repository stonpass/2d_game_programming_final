extends Node2D

@onready var sprite: Sprite2D = $Sprite2D

@export var mouse_cursor: Texture2D
@export var mouse_on_cursor: Texture2D
@export var mouse_attack_cursor: Texture2D
@export var mouse_attack_on_cursor: Texture2D

const HOVER_CHECK_INTERVAL := 0.08

var current_hovered_object = null
var hover_check_timer: float = 0.0

func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)
	call_deferred("_move_to_top_canvas_layer")
	z_as_relative = false
	z_index = 0
	sprite.z_as_relative = false
	sprite.z_index = 0
	sprite.centered = true

func _move_to_top_canvas_layer():
	if get_parent() is CanvasLayer:
		return
	var top_layer = CanvasLayer.new()
	top_layer.name = "PointerTopLayer"
	top_layer.layer = 128
	top_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	var parent_node = get_parent()
	if parent_node:
		parent_node.remove_child(self)
		parent_node.add_child(top_layer)
		top_layer.add_child(self)

func _process(delta):
	position = get_viewport().get_mouse_position()
	_update_cursor_image()

	hover_check_timer -= delta
	if hover_check_timer <= 0.0:
		_handle_unit_hover_by_code()
		hover_check_timer = HOVER_CHECK_INTERVAL

func _update_cursor_image():
	var attack_held = Input.is_key_pressed(KEY_A) and _has_selected_ally()
	var right_click_held = Input.is_action_pressed("right_click")
	if attack_held and right_click_held:
		sprite.texture = mouse_attack_on_cursor
	elif attack_held:
		sprite.texture = mouse_attack_cursor
	elif right_click_held:
		sprite.texture = mouse_on_cursor
	else:
		sprite.texture = mouse_cursor

func _has_selected_ally() -> bool:
	if not UnitManager or not ("unit_selected" in UnitManager):
		return false
	for selected in UnitManager.unit_selected:
		if is_instance_valid(selected) and selected.is_in_group("Ally"):
			return true
	return false

func _handle_unit_hover_by_code():
	var world_mouse_position = _get_world_mouse_position()
	var closest_unit = null
	var min_distance = INF

	for unit in get_tree().get_nodes_in_group("Unit"):
		if not is_instance_valid(unit):
			continue
		if unit.has_method("get_rect") and unit.get_rect().has_point(world_mouse_position):
			var dist = world_mouse_position.distance_squared_to(unit.global_position)
			if dist < min_distance:
				min_distance = dist
				closest_unit = unit

	var closest_object = closest_unit
	for object in _get_hoverable_world_objects():
		if not is_instance_valid(object):
			continue
		if object is CanvasItem and not object.visible:
			continue
		if object.has_method("get_rect") and object.get_rect().has_point(world_mouse_position):
			var dist = world_mouse_position.distance_squared_to(object.global_position)
			if dist < min_distance:
				min_distance = dist
				closest_object = object

	if closest_object == current_hovered_object:
		return

	if is_instance_valid(current_hovered_object) and current_hovered_object.has_method("set_hover"):
		current_hovered_object.set_hover(false)

	current_hovered_object = closest_object

	if is_instance_valid(current_hovered_object) and current_hovered_object.has_method("set_hover"):
		current_hovered_object.set_hover(true)

func _get_world_mouse_position() -> Vector2:
	var current_scene = get_tree().current_scene
	if current_scene:
		return current_scene.get_global_mouse_position()
	return get_global_mouse_position()

func _get_hoverable_world_objects() -> Array:
	var objects: Array = []
	objects.append_array(get_tree().get_nodes_in_group("ResourceDeposit"))
	objects.append_array(get_tree().get_nodes_in_group("Ruins"))
	objects.append_array(get_tree().get_nodes_in_group("Building"))
	for dropoff in get_tree().get_nodes_in_group("ResourceDropoff"):
		if not objects.has(dropoff):
			objects.append(dropoff)
	return objects
