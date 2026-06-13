extends Node2D

const EMPTY_SOURCE_ID := 0
const OBSTACLE_SOURCE_ID := 1
const RAMP_SOURCE_ID := 2
const DEFAULT_ATLAS := Vector2i(0, 0)
const RESOURCE_BUILD_CLEARANCE_TILES := 7
const BUILDING_UNIT_BLOCK_HEIGHT_RATIO := 0.5
const MUSEUM_TEXTURE = preload("res://assets/building/building_museum.png")
const RESTAURANT_TEXTURE = preload("res://assets/building/building_restaurant.png")

@export var tile_map_path: NodePath
@export var building_scene: PackedScene
@export var footprint_tiles: Vector2i = Vector2i(4, 4)
@export var mineral_cost: int = 50
@export var gas_cost: int = 0

var active := false
var tile_map: TileMapLayer
var preview_cells: Array[Vector2i] = []
var can_place := false
var can_afford_building := true
var active_building_config: Dictionary = {}

func _ready():
	tile_map = get_node_or_null(tile_map_path)
	add_to_group("BuildingPlacement")
	await get_tree().process_frame
	_mark_existing_obstacles()

func _process(_delta):
	if active:
		_update_preview()
	queue_redraw()

func _unhandled_input(event):
	if not active:
		return
	if event.is_action_pressed("ui_cancel") or (event is InputEventKey and event.is_pressed() and not event.is_echo() and event.keycode == KEY_ESCAPE):
		cancel()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("right_click"):
		cancel()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("left_click"):
		if can_place:
			_place_building()
		else:
			_show_invalid_place_notice()
		get_viewport().set_input_as_handled()

func start_building(building_config: Dictionary = {}):
	active_building_config = building_config.duplicate()
	if active_building_config.is_empty():
		active_building_config = _get_command_center_config()
	footprint_tiles = active_building_config.get("footprint_tiles", Vector2i(20, 8))
	if not _can_afford_build_cost():
		_show_cost_failure_notice()
		active_building_config.clear()
		active = false
		preview_cells.clear()
		queue_redraw()
		return
	active = true
	_update_preview()

func cancel():
	active = false
	preview_cells.clear()
	queue_redraw()

func _update_preview():
	if not tile_map:
		return
	var origin = _get_origin_cell_from_bottom(get_global_mouse_position(), footprint_tiles)
	if _requires_foundation():
		var foundation = _get_foundation_at_position(get_global_mouse_position())
		if foundation:
			var foundation_size = foundation.get_footprint_tiles() if foundation.has_method("get_footprint_tiles") else footprint_tiles
			origin = _get_origin_cell(foundation.global_position, foundation_size)
			footprint_tiles = foundation_size
		else:
			origin = _get_origin_cell(get_global_mouse_position(), footprint_tiles)
	preview_cells = _get_cells(origin, footprint_tiles)
	can_afford_building = _can_afford_build_cost()
	can_place = _can_place_cells(preview_cells) and can_afford_building

func _place_building():
	if not building_scene or preview_cells.is_empty():
		return
	var builder = _get_selected_builder()
	if not builder:
		return
	var cells := preview_cells.duplicate()
	var foundation = _get_matching_foundation(cells) if _requires_foundation() else null
	if _requires_foundation():
		if not foundation:
			foundation = _get_foundation_at_position(get_global_mouse_position())
			if foundation:
				var foundation_size = foundation.get_footprint_tiles() if foundation.has_method("get_footprint_tiles") else footprint_tiles
				footprint_tiles = foundation_size
				cells = _get_cells(_get_origin_cell(foundation.global_position, foundation_size), foundation_size)
				preview_cells = cells.duplicate()
		if not foundation:
			_show_invalid_place_notice()
			return
		active_building_config["foundation_node"] = foundation
	if not _spend_build_cost():
		return
	var center = _cells_bottom_center(cells)
	var blocked_cells: Array[Vector2i] = _get_building_unit_block_cells(cells)
	_set_cells_obstacle(blocked_cells)
	if builder.has_method("start_build_order"):
		var accepted = builder.start_build_order(center, building_scene, cells, self, active_building_config.duplicate(), _is_shift_pressed())
		if not accepted:
			clear_build_cells(blocked_cells)
			if _is_shift_pressed():
				_update_preview()
			else:
				cancel()
			return
		_play_student_voice("yes")
	if _is_shift_pressed():
		_update_preview()
	else:
		cancel()

func create_construction_site(center: Vector2, builder: Node2D = null, cells: Array = [], building_config: Dictionary = {}):
	var building = building_scene.instantiate()
	_apply_building_config(building, building_config)
	var parent = get_tree().current_scene.find_child("Resources", true, false)
	if not parent:
		parent = get_parent()
	parent.add_child(building)
	building.global_position = center
	if building.has_method("start_construction"):
		building.start_construction(builder, cells, self)
	return building

func _is_shift_pressed() -> bool:
	return Input.is_key_pressed(KEY_SHIFT)

func _get_selected_builder():
	var manager = get_tree().get_first_node_in_group("UnitManager")
	if not manager or not ("unit_selected" in manager):
		return null
	var best_builder = null
	var best_load = INF
	for unit in manager.unit_selected:
		if is_instance_valid(unit) and unit.is_in_group("Ally") and "can_build" in unit and unit.can_build:
			var build_load = unit.get_build_order_load() if unit.has_method("get_build_order_load") else 0
			if build_load < best_load:
				best_load = build_load
				best_builder = unit
	return best_builder

func _spend_build_cost() -> bool:
	var hud = get_tree().current_scene.find_child("HUD", true, false) if get_tree().current_scene else null
	if not hud or not hud.has_method("spend_resource"):
		return true
	return hud.spend_resource(active_building_config.get("mineral_cost", mineral_cost), active_building_config.get("gas_cost", gas_cost))

func _can_afford_build_cost() -> bool:
	var hud = get_tree().current_scene.find_child("HUD", true, false) if get_tree().current_scene else null
	if not hud or not hud.has_method("can_afford"):
		return true
	return hud.can_afford(active_building_config.get("mineral_cost", mineral_cost), active_building_config.get("gas_cost", gas_cost))

func _show_cost_failure_notice():
	var hud = get_tree().current_scene.find_child("HUD", true, false) if get_tree().current_scene else null
	if not hud or not hud.has_method("show_notice"):
		return
	if hud.has_method("get_cost_failure_message"):
		var message = hud.get_cost_failure_message(active_building_config.get("mineral_cost", mineral_cost), active_building_config.get("gas_cost", gas_cost))
		if not message.is_empty():
			hud.show_notice(message)

func _show_invalid_place_notice(message_override: String = ""):
	_play_student_voice("error")
	var hud = get_tree().current_scene.find_child("HUD", true, false) if get_tree().current_scene else null
	if hud and hud.has_method("show_notice"):
		if not message_override.is_empty():
			hud.show_notice(message_override)
		elif _requires_foundation():
			hud.show_notice("유적지 위치에만 건설할 수 있습니다")
		else:
			hud.show_notice("해당 위치에는 건설할 수 없습니다")

func _play_student_voice(voice_type: String):
	var manager = get_tree().get_first_node_in_group("UnitManager")
	if manager and manager.has_method("play_student_voice"):
		manager.play_student_voice(voice_type)

func _apply_building_config(building: Node, building_config: Dictionary):
	for key in building_config.keys():
		if key in building:
			building.set(key, building_config[key])

func _get_command_center_config() -> Dictionary:
	return {
		"building_name": "행소박물관",
		"description": "행소박물관이다. 학생을 생산할 수 있다",
		"can_produce_students": true,
		"can_produce_units": true,
		"production_unit_scene": preload("res://scenes/units/student.tscn"),
		"production_unit_icon": preload("res://icon/stduent_icon.png"),
		"production_unit_button_icon_path": "res://assets/btu/stduent_btu.png",
		"production_unit_name": "학생",
		"production_time": 17.0,
		"production_population_cost": 1,
		"production_mineral_cost": 50,
		"production_gas_cost": 0,
		"supply_bonus": 10,
		"accepts_resource_dropoff": true,
		"max_hp": 1500,
		"build_time": 40.0,
		"footprint_tiles": Vector2i(20, 8),
		"visual_ground_ratio": 0.8,
		"icon_texture": MUSEUM_TEXTURE,
		"preview_texture": MUSEUM_TEXTURE,
		"mineral_cost": 400,
		"gas_cost": gas_cost
	}

func _mark_existing_obstacles():
	for node in get_tree().get_nodes_in_group("ResourceDeposit") + get_tree().get_nodes_in_group("Building") + get_tree().get_nodes_in_group("ResourceDropoff") + get_tree().get_nodes_in_group("Ruins"):
		if is_instance_valid(node) and node is Node2D:
			var size = footprint_tiles
			if node.has_method("get_footprint_tiles"):
				size = node.get_footprint_tiles()
			elif "footprint_tiles" in node:
				size = node.footprint_tiles
			var origin = _get_origin_cell_from_bottom(node.global_position, size) if node.is_in_group("Building") else _get_origin_cell(node.global_position, size)
			var cells := _get_cells(origin, size)
			if node.is_in_group("Building"):
				_set_cells_obstacle(_get_building_unit_block_cells(cells))
			else:
				_set_cells_obstacle(cells)

func _can_place_cells(cells: Array[Vector2i]) -> bool:
	var foundation = _get_matching_foundation(cells) if _requires_foundation() else null
	if _requires_foundation():
		if not foundation:
			return false
		return _can_place_on_foundation_cells(cells, foundation)
	for cell in cells:
		if not _is_cell_buildable(cell):
			return false
	if _is_too_close_to_resource(cells):
		return false
	if _intersects_existing_building_cells(cells):
		return false
	return true

func _can_place_on_foundation_cells(cells: Array[Vector2i], foundation: Node2D) -> bool:
	var size = footprint_tiles
	if foundation.has_method("get_footprint_tiles"):
		size = foundation.get_footprint_tiles()
	elif "footprint_tiles" in foundation:
		size = foundation.footprint_tiles
	var foundation_cells = _get_cells(_get_origin_cell(foundation.global_position, size), size)
	var allowed := {}
	for cell in foundation_cells:
		allowed[cell] = true
	for cell in cells:
		if not allowed.has(cell):
			return false
	return true

func _requires_foundation() -> bool:
	return not str(active_building_config.get("requires_foundation_group", "")).is_empty()

func _get_matching_foundation(cells: Array[Vector2i]) -> Node2D:
	if not _requires_foundation() or cells.is_empty():
		return null
	var group_name := str(active_building_config.get("requires_foundation_group", ""))
	var wanted := {}
	for cell in cells:
		wanted[cell] = true
	for node in get_tree().get_nodes_in_group(group_name):
		if not is_instance_valid(node) or not (node is Node2D):
			continue
		if "used" in node and node.used:
			continue
		var size = footprint_tiles
		if node.has_method("get_footprint_tiles"):
			size = node.get_footprint_tiles()
		elif "footprint_tiles" in node:
			size = node.footprint_tiles
		var foundation_cells = _get_cells(_get_origin_cell(node.global_position, size), size)
		if foundation_cells.size() != cells.size():
			continue
		var matches := true
		for foundation_cell in foundation_cells:
			if not wanted.has(foundation_cell):
				matches = false
				break
		if matches:
			return node
	var foundation = _get_foundation_at_position(get_global_mouse_position())
	if foundation:
		var foundation_size = foundation.get_footprint_tiles() if foundation.has_method("get_footprint_tiles") else footprint_tiles
		var foundation_cells = _get_cells(_get_origin_cell(foundation.global_position, foundation_size), foundation_size)
		if foundation_cells.size() == cells.size():
			return foundation
	return null

func _get_foundation_at_position(world_pos: Vector2) -> Node2D:
	if not _requires_foundation():
		return null
	var group_name := str(active_building_config.get("requires_foundation_group", ""))
	for node in get_tree().get_nodes_in_group(group_name):
		if not is_instance_valid(node) or not (node is Node2D):
			continue
		if "used" in node and node.used:
			continue
		if node.has_method("get_rect") and node.get_rect().grow(10.0).has_point(world_pos):
			return node
		var size = Vector2(footprint_tiles * tile_map.tile_set.tile_size)
		if Rect2(node.global_position - size * 0.5, size).grow(10.0).has_point(world_pos):
			return node
	return null

func _is_cell_buildable(cell: Vector2i) -> bool:
	if tile_map.get_cell_source_id(cell) != EMPTY_SOURCE_ID:
		return false
	var data = tile_map.get_cell_tile_data(cell)
	return data != null and data.get_custom_data("can_build") == true

func _is_too_close_to_resource(cells: Array[Vector2i]) -> bool:
	if _requires_foundation() or cells.is_empty() or not tile_map:
		return false
	var clearance := float(RESOURCE_BUILD_CLEARANCE_TILES * tile_map.tile_set.tile_size.x)
	var build_rect := _get_cells_world_rect(cells).grow(clearance)
	for node in get_tree().get_nodes_in_group("ResourceDeposit") + get_tree().get_nodes_in_group("Ruins"):
		if not is_instance_valid(node) or not (node is Node2D):
			continue
		if not _is_active_resource_blocker(node):
			continue
		if "is_under_construction" in node and node.is_under_construction:
			continue
		var resource_rect := Rect2(node.global_position, Vector2.ZERO)
		if node.has_method("get_rect"):
			resource_rect = node.get_rect()
		else:
			resource_rect = Rect2(node.global_position - Vector2(clearance, clearance) * 0.5, Vector2(clearance, clearance))
		if build_rect.intersects(resource_rect) or build_rect.has_point(node.global_position):
			return true
	return false

func _is_active_resource_blocker(node: Node) -> bool:
	if node.has_method("is_depleted") and bool(node.call("is_depleted")):
		return false
	if "resource_amount" in node and int(node.get("resource_amount")) <= 0:
		return false
	if "used" in node and bool(node.get("used")):
		return false
	return true

func _intersects_existing_building_cells(cells: Array[Vector2i]) -> bool:
	if cells.is_empty():
		return false
	var requested: Dictionary = {}
	for cell in cells:
		requested[cell] = true
	for building in get_tree().get_nodes_in_group("Building"):
		if not is_instance_valid(building) or not ("occupied_cells" in building):
			continue
		for occupied_cell in building.occupied_cells:
			if requested.has(occupied_cell):
				return true
	return false

func _get_cells_world_rect(cells: Array[Vector2i]) -> Rect2:
	var min_cell := cells[0]
	var max_cell := cells[0]
	for cell in cells:
		min_cell.x = mini(min_cell.x, cell.x)
		min_cell.y = mini(min_cell.y, cell.y)
		max_cell.x = maxi(max_cell.x, cell.x)
		max_cell.y = maxi(max_cell.y, cell.y)
	var tile_size = tile_map.tile_set.tile_size
	var half_tile = Vector2(tile_size.x, tile_size.y) * 0.5
	var local_min = tile_map.map_to_local(min_cell) - half_tile
	var local_max = tile_map.map_to_local(max_cell) + half_tile
	return Rect2(tile_map.to_global(local_min), local_max - local_min)

func _set_cells_obstacle(cells: Array[Vector2i]):
	for cell in cells:
		tile_map.set_cell(cell, OBSTACLE_SOURCE_ID, DEFAULT_ATLAS)

func _get_building_unit_block_cells(cells: Array[Vector2i]) -> Array[Vector2i]:
	var blocked_cells: Array[Vector2i] = []
	if cells.is_empty():
		return blocked_cells
	var min_y: int = cells[0].y
	var max_y: int = cells[0].y
	for cell in cells:
		min_y = mini(min_y, cell.y)
		max_y = maxi(max_y, cell.y)
	var row_count: int = max_y - min_y + 1
	var blocked_rows: int = maxi(1, ceili(float(row_count) * BUILDING_UNIT_BLOCK_HEIGHT_RATIO))
	var first_blocked_y: int = max_y - blocked_rows + 1
	for cell in cells:
		if cell.y >= first_blocked_y:
			blocked_cells.append(cell)
	return blocked_cells

func clear_build_cells(cells: Array):
	if not tile_map:
		return
	for cell in cells:
		tile_map.set_cell(cell, EMPTY_SOURCE_ID, DEFAULT_ATLAS)

func mark_node_obstacle(node: Node2D):
	if not tile_map or not is_instance_valid(node):
		return
	var size = footprint_tiles
	if node.has_method("get_footprint_tiles"):
		size = node.get_footprint_tiles()
	elif "footprint_tiles" in node:
		size = node.footprint_tiles
	var origin = _get_origin_cell_from_bottom(node.global_position, size) if node.is_in_group("Building") else _get_origin_cell(node.global_position, size)
	var cells := _get_cells(origin, size)
	if node.is_in_group("Building"):
		_set_cells_obstacle(_get_building_unit_block_cells(cells))
	else:
		_set_cells_obstacle(cells)

func clear_node_obstacle(node: Node2D):
	if not tile_map or not is_instance_valid(node):
		return
	var size = footprint_tiles
	if node.has_method("get_footprint_tiles"):
		size = node.get_footprint_tiles()
	elif "footprint_tiles" in node:
		size = node.footprint_tiles
	var origin = _get_origin_cell_from_bottom(node.global_position, size) if node.is_in_group("Building") else _get_origin_cell(node.global_position, size)
	var cells := _get_cells(origin, size)
	if node.is_in_group("Building"):
		clear_build_cells(_get_building_unit_block_cells(cells))
	else:
		clear_build_cells(cells)

func _get_origin_cell(world_pos: Vector2, size: Vector2i) -> Vector2i:
	var local_pos = tile_map.to_local(world_pos)
	var center_cell = tile_map.local_to_map(local_pos)
	return center_cell - Vector2i(floori(size.x / 2.0), floori(size.y / 2.0))

func _get_cells(origin: Vector2i, size: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for y in range(size.y):
		for x in range(size.x):
			cells.append(origin + Vector2i(x, y))
	return cells

func _cells_bottom_center(cells: Array[Vector2i]) -> Vector2:
	var min_cell := cells[0]
	var max_cell := cells[0]
	for cell in cells:
		min_cell.x = mini(min_cell.x, cell.x)
		min_cell.y = mini(min_cell.y, cell.y)
		max_cell.x = maxi(max_cell.x, cell.x)
		max_cell.y = maxi(max_cell.y, cell.y)
	var local_a = tile_map.map_to_local(min_cell)
	var local_b = tile_map.map_to_local(max_cell)
	var local_center = (local_a + local_b) * 0.5
	local_center.y += tile_map.tile_set.tile_size.y * 0.5
	return tile_map.to_global(local_center)

func _get_origin_cell_from_bottom(world_pos: Vector2, size: Vector2i) -> Vector2i:
	var local_pos = tile_map.to_local(world_pos)
	local_pos.y -= size.y * tile_map.tile_set.tile_size.y * 0.5
	var center_cell = tile_map.local_to_map(local_pos)
	return center_cell - Vector2i(floori(size.x / 2.0), floori(size.y / 2.0))

func _draw():
	if not active or not tile_map:
		return
	for cell in preview_cells:
		var source_id = tile_map.get_cell_source_id(cell)
		var buildable = _is_cell_buildable(cell)
		if _requires_foundation() and can_place:
			buildable = true
		var cell_ok := buildable and can_afford_building and can_place
		var fill := _get_preview_fill(source_id, cell_ok)
		var line := Color(0.0, 1.0, 0.3, 0.9) if cell_ok else Color(1.0, 0.16, 0.1, 0.95)
		var center = to_local(tile_map.to_global(tile_map.map_to_local(cell)))
		var rect = Rect2(center - Vector2(8, 8), Vector2(16, 16))
		draw_rect(rect, fill, true)
		draw_rect(rect, line, false, 1.0)
	_draw_building_preview()

func _draw_building_preview():
	var texture = active_building_config.get("preview_texture", null)
	if not texture or not texture is Texture2D or preview_cells.is_empty():
		return
	var ratio = clamp(float(active_building_config.get("visual_ground_ratio", 0.8)), 0.1, 1.0)
	var scale_override = float(active_building_config.get("visual_scale_override", 0.0))
	var tile_size = tile_map.tile_set.tile_size
	var footprint_size = Vector2(footprint_tiles * tile_size)
	var visual_height = footprint_size.y / ratio
	var visual_size = Vector2(footprint_size.x, visual_height)
	if scale_override > 0.0:
		visual_size = texture.get_size() * scale_override
	var bottom_center = to_local(_cells_bottom_center(preview_cells))
	var preview_rect = Rect2(bottom_center + Vector2(-visual_size.x * 0.5, -visual_size.y), visual_size)
	draw_texture_rect(texture, preview_rect, false, Color(0.45, 0.45, 0.45, 0.55))

func _get_preview_fill(source_id: int, buildable: bool) -> Color:
	if buildable:
		return Color(0.0, 0.85, 0.2, 0.42)
	match source_id:
		EMPTY_SOURCE_ID:
			return Color(1.0, 0.08, 0.05, 0.38)
		RAMP_SOURCE_ID:
			return Color(1.0, 0.08, 0.05, 0.5)
		OBSTACLE_SOURCE_ID:
			return Color(0.75, 0.02, 0.02, 0.58)
		_:
			return Color(0.95, 0.08, 0.04, 0.5)
