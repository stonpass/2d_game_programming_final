extends Area2D

@export var footprint_tiles: Vector2i = Vector2i(20, 8)
@export var tile_size: int = 16
@export var visual_ground_ratio: float = 0.8
@export var visual_scale_override: float = 0.0
@export var building_name: String = "행소박물관"
@export var description: String = "행소박물관이다. 학생을 생산할 수 있다"
@export var icon_texture: Texture2D = preload("res://assets/building/building_museum.png")
@export var max_hp: int = 1500
@export var build_time: float = 15.0
@export var student_scene: PackedScene = preload("res://scenes/units/student.tscn")
@export var student_icon_texture: Texture2D = preload("res://icon/test_unitIcon.png")
@export var student_production_time: float = 17.0
@export var max_production_queue: int = 5
@export var student_population_cost: int = 1
@export var can_produce_students: bool = true
@export var production_unit_scene: PackedScene = preload("res://scenes/units/student.tscn")
@export var production_unit_icon: Texture2D = preload("res://icon/stduent_icon.png")
@export var production_unit_button_icon_path: String = "res://assets/btu/stduent_btu.png"
@export var production_unit_name: String = "학생"
@export var production_time: float = 17.0
@export var production_population_cost: int = 1
@export var production_mineral_cost: int = 50
@export var production_gas_cost: int = 0
@export var can_produce_units: bool = true
@export var supply_bonus: int = 0
@export var accepts_resource_dropoff: bool = true
@export var is_enemy_building: bool = false
@export var provides_resource: bool = false
@export var resource_amount: int = 0
@export var max_resource_amount: int = 0
@export var resource_kind: String = "mineral"
@export var gather_time_override: float = 0.0
@export var display_name: String = ""
@export var lock_footprint_to_config: bool = false
@export var foundation_node: Node2D = null

var hp: int = 1500:
	set(value):
		hp = clamp(value, 0, max_hp)
		if hp <= 0:
			_destroy()
		else:
			queue_redraw()
			_refresh_selection_info_if_selected()
var is_under_construction: bool = false
var construction_progress: float = 1.0
var builder: Node2D = null
var occupied_cells: Array = []
var placement_controller: Node = null
var production_queue: Array[String] = []
var production_timer: float = 0.0
var rally_position: Vector2 = Vector2.ZERO
var rally_resource: Node2D = null
var has_rally_point: bool = false
var supply_applied: bool = false
var production_sprite_timer: float = 0.0
var production_sprite_on: bool = false
var waiting_for_builder: bool = false
var reserved_builder: Node2D = null
var reservation_required: bool = false
var construction_started: bool = false
var last_construction_progress_frame: int = -1
var lab_pending: bool = false
var lab_pending_cost_paid: bool = false
var lab_reserved_cells: Array[Vector2i] = []
var lab_site: Node2D = null
var lab_construction_active: bool = false
var lab_construction_timer: float = 0.0
var active_upgrade_id: String = ""

const SELECTION_RING_SCRIPT = preload("res://scripts/selection_ring.gd")
const MUSEUM_TEXTURE = preload("res://assets/building/building_museum.png")
const MUSEUM_ON_TEXTURE = preload("res://assets/building/building_museum_on.png")
const RESTAURANT_TEXTURE = preload("res://assets/building/building_restaurant.png")
const DOK_TEXTURE = preload("res://assets/building/building_dok.png")
const DOK_ON_TEXTURE = preload("res://assets/building/building_dok_on.png")
const LAB_TEXTURE = preload("res://assets/building/building_technic.png")
const LAB_ON_TEXTURE = preload("res://assets/building/building_technic_on.png")
const EXCAVATION_TEXTURE = preload("res://assets/building/excavation_site.png")
const TRAINING_TEXTURE = preload("res://assets/building/building_armitraing.png")
const CONTACT_HEIGHT_RATIO := 0.5
const DROPOFF_TOP_HEIGHT_RATIO := 0.5
const TEST_CONSTRUCTION_RANGE_PADDING := 100.0
const LAB_BUTTON_TEXTURE = preload("res://assets/btu/technic_btu.png")
const EMPTY_TILE_SOURCE_ID := 0
const MUSEUM_BUILDING_NAME := "행소박물관"
const RESTAURANT_BUILDING_NAME := "공대식당"
const DOK_BUILDING_NAME := "덕래관"
const LAB_BUILDING_NAME := "연구실"
const LAB_QUEUE_NAME := "__LAB__"
const PROFESSOR_QUEUE_NAME := "교수"
const LAB_MINERAL_COST := 50
const LAB_GAS_COST := 50
const LAB_BUILD_TIME := 25.0
const LAB_FOOTPRINT_TILES := Vector2i(2, 6)
const LAB_VISUAL_SCALE := 0.256
const PROFESSOR_SCENE: PackedScene = preload("res://scenes/units/professor.tscn")
const PROFESSOR_ICON: Texture2D = preload("res://icon/professor_icon.png")
const PROFESSOR_BUTTON_PATH := "res://assets/btu/professor_btu.png"
const PROFESSOR_PRODUCTION_TIME := 50.0
const PROFESSOR_POPULATION_COST := 5
const PROFESSOR_MINERAL_COST := 150
const PROFESSOR_GAS_COST := 50
const ARMI_QUEUE_NAME := "예비군"
const ARMI_SCENE: PackedScene = preload("res://scenes/units/armi.tscn")
const ARMI_ICON: Texture2D = preload("res://icon/armi_icon.png")
const ARMI_BUTTON_PATH := "res://assets/btu/armi_btu.png"
const ARMI_PRODUCTION_TIME := 30.0
const ARMI_POPULATION_COST := 3
const ARMI_MINERAL_COST := 75
const ARMI_GAS_COST := 25
const TRAINING_BUILDING_NAME := "훈련소"
const CONSTRUCTION_BANDS := 5
const PRODUCTION_SPRITE_INTERVAL := 0.3
const DEPTH_SORT_OFFSET := 2048
const EXCAVATION_BUILDING_NAME := "발굴지"

var hover_mode: bool = false
var select_mode: bool = false
var selection_ring
var last_bullet_hit_effect_msec: int = 0

func _ready():
	add_to_group("Building")
	_refresh_resource_dropoff_group()
	_refresh_resource_deposit_group()
	if is_enemy_building:
		add_to_group("Enemy")
	else:
		add_to_group("Ally")
	_update_depth_sort()
	hp = max_hp
	_configure_visual_sprite()
	_update_collision_shape()
	_create_selection_ring()
	queue_redraw()

func _process(delta):
	_update_depth_sort()
	_process_construction(delta)
	_process_production(delta)
	if lab_construction_active:
		_process_laboratory_construction(delta)
	_process_active_upgrade_display()
	_update_production_sprite(delta)
	if lab_pending:
		queue_redraw()

func _update_depth_sort():
	z_index = clampi(int(global_position.y) + DEPTH_SORT_OFFSET, 0, 4096)

func get_current_buttons() -> Array:
	if is_under_construction:
		return []
	if _is_training_building():
		return _get_training_upgrade_buttons()
	if _is_laboratory_building():
		return _get_laboratory_upgrade_buttons()
	if not can_produce_units:
		return []
	var unit_tooltip := "[color=#ffd84a]%s[/color]\n생산 시간 [color=#56a8ff]%d초[/color]\n필요자원: [color=#56a8ff]%d/%d[/color]\n인구수: [color=#ff9f33]%d[/color]" % [production_unit_name, int(_get_display_production_time(production_time)), production_mineral_cost, production_gas_cost, production_population_cost]
	if lab_construction_active:
		unit_tooltip = "부속건물을 건설 중입니다"
	var buttons = [
		{"index": 0, "key": KEY_S, "icon_path": production_unit_button_icon_path, "function": "_on_train_unit_pressed", "disabled": lab_construction_active, "tooltip": unit_tooltip}
	]
	if building_name == DOK_BUILDING_NAME:
		var lab_done := _has_laboratory()
		buttons.append({
			"index": 6,
			"key": KEY_B,
			"icon_path": "res://assets/btu/technic_btu.png",
			"function": "_on_build_lab_pressed",
			"disabled": lab_done,
			"tooltip": "[color=#ffd84a]연구실[/color]\n건설시간 [color=#56a8ff]%d초[/color]\n필요자원: [color=#56a8ff]%d/%d[/color]\n덕래관 우측에 건설" % [int(LAB_BUILD_TIME), LAB_MINERAL_COST, LAB_GAS_COST]
		})
	if building_name == DOK_BUILDING_NAME:
		var can_train_professor := _has_completed_laboratory()
		buttons.append({
			"index": 1,
			"key": KEY_T,
			"icon_path": PROFESSOR_BUTTON_PATH,
			"function": "_on_train_professor_pressed",
			"disabled": lab_construction_active or not can_train_professor,
			"tooltip": "부속건물을 건설 중입니다" if lab_construction_active else "[color=#ffd84a]교수[/color]\n생산 시간 [color=#56a8ff]%d초[/color]\n필요자원: [color=#56a8ff]%d/%d[/color]\n인구수: [color=#ff9f33]%d[/color]\n필요조건 [color=%s]연구실[/color]" % [int(_get_display_production_time(PROFESSOR_PRODUCTION_TIME)), PROFESSOR_MINERAL_COST, PROFESSOR_GAS_COST, PROFESSOR_POPULATION_COST, "#56a8ff" if can_train_professor else "#ff4a4a"]
		})
	if building_name == DOK_BUILDING_NAME:
		var can_train_armi := _has_completed_building(TRAINING_BUILDING_NAME)
		buttons.append({
			"index": 2,
			"key": KEY_A,
			"icon_path": ARMI_BUTTON_PATH,
			"function": "_on_train_armi_pressed",
			"disabled": lab_construction_active or not can_train_armi,
			"tooltip": "부속건물을 건설 중입니다" if lab_construction_active else "[color=#ffd84a]예비군[/color]\n생산 시간 [color=#56a8ff]%d초[/color]\n필요자원: [color=#56a8ff]%d/%d[/color]\n인구수: [color=#ff9f33]%d[/color]\n필요조건 [color=%s]훈련소[/color]" % [int(_get_display_production_time(ARMI_PRODUCTION_TIME)), ARMI_MINERAL_COST, ARMI_GAS_COST, ARMI_POPULATION_COST, "#56a8ff" if can_train_armi else "#ff4a4a"]
		})
	return buttons

func _get_training_upgrade_buttons() -> Array:
	var buttons: Array = []
	_append_upgrade_button(buttons, 0, KEY_B, "body", "_on_upgrade_body_pressed")
	_append_upgrade_button(buttons, 1, KEY_V, "power", "_on_upgrade_power_pressed")
	return buttons

func _get_laboratory_upgrade_buttons() -> Array:
	var buttons: Array = []
	_append_upgrade_button(buttons, 0, KEY_S, "student", "_on_upgrade_student_trait_pressed")
	_append_upgrade_button(buttons, 1, KEY_W, "m_student", "_on_upgrade_m_student_trait_pressed")
	_append_upgrade_button(buttons, 2, KEY_T, "professor", "_on_upgrade_professor_trait_pressed")
	_append_upgrade_button(buttons, 3, KEY_A, "armi", "_on_upgrade_armi_trait_pressed")
	return buttons

func _append_upgrade_button(buttons: Array, index: int, key: Key, upgrade_id: String, function_name: String):
	var manager = get_tree().get_first_node_in_group("UnitManager")
	if not manager or not manager.has_method("can_start_upgrade"):
		return
	if manager.get_upgrade_level(upgrade_id) >= _get_upgrade_max_level(upgrade_id):
		return
	var disabled := false
	if manager.has_method("can_start_upgrade_for_building"):
		disabled = not active_upgrade_id.is_empty() or not manager.can_start_upgrade_for_building(upgrade_id, get_instance_id())
	else:
		disabled = not active_upgrade_id.is_empty() or not manager.can_start_upgrade(upgrade_id)
	buttons.append({
		"index": index,
		"key": key,
		"icon_path": manager.get_upgrade_icon_path(upgrade_id),
		"function": function_name,
		"disabled": disabled,
		"tooltip": manager.get_upgrade_tooltip(upgrade_id)
	})

func _is_training_building() -> bool:
	return _get_building_texture() == TRAINING_TEXTURE

func _is_laboratory_building() -> bool:
	return _get_building_texture() == LAB_TEXTURE

func _get_upgrade_max_level(upgrade_id: String) -> int:
	return 3 if upgrade_id == "body" or upgrade_id == "power" else 1

func _on_train_student_pressed():
	_on_train_unit_pressed()

func _on_train_unit_pressed():
	if not can_produce_units:
		return
	_enqueue_unit_production(production_unit_name, production_unit_scene if production_unit_scene else student_scene, production_unit_icon, production_time, production_population_cost, production_mineral_cost, production_gas_cost)

func _on_train_professor_pressed():
	if building_name != DOK_BUILDING_NAME:
		return
	if not _has_completed_laboratory():
		_show_notice("연구실이 필요합니다")
		return
	_enqueue_unit_production(PROFESSOR_QUEUE_NAME, PROFESSOR_SCENE, PROFESSOR_ICON, PROFESSOR_PRODUCTION_TIME, PROFESSOR_POPULATION_COST, PROFESSOR_MINERAL_COST, PROFESSOR_GAS_COST)

func _on_train_armi_pressed():
	if building_name != DOK_BUILDING_NAME:
		return
	if not _has_completed_building(TRAINING_BUILDING_NAME):
		_show_notice("훈련소가 필요합니다")
		return
	_enqueue_unit_production(ARMI_QUEUE_NAME, ARMI_SCENE, ARMI_ICON, ARMI_PRODUCTION_TIME, ARMI_POPULATION_COST, ARMI_MINERAL_COST, ARMI_GAS_COST)

func _on_upgrade_body_pressed():
	_start_upgrade("body")

func _on_upgrade_power_pressed():
	_start_upgrade("power")

func _on_upgrade_student_trait_pressed():
	_start_upgrade("student")

func _on_upgrade_m_student_trait_pressed():
	_start_upgrade("m_student")

func _on_upgrade_professor_trait_pressed():
	_start_upgrade("professor")

func _on_upgrade_armi_trait_pressed():
	_start_upgrade("armi")

func _start_upgrade(upgrade_id: String):
	if not active_upgrade_id.is_empty():
		return
	var manager = get_tree().get_first_node_in_group("UnitManager")
	if manager and manager.has_method("start_upgrade_for_building"):
		if manager.start_upgrade_for_building(upgrade_id, get_instance_id()):
			active_upgrade_id = upgrade_id
			_refresh_selection_info_if_selected()
	elif manager and manager.has_method("start_upgrade"):
		if manager.start_upgrade(upgrade_id):
			active_upgrade_id = upgrade_id
			_refresh_selection_info_if_selected()

func _process_active_upgrade_display():
	if active_upgrade_id.is_empty():
		return
	var manager = get_tree().get_first_node_in_group("UnitManager")
	if not manager or not manager.has_method("is_upgrade_in_progress") or not manager.is_upgrade_in_progress(active_upgrade_id):
		active_upgrade_id = ""
		_refresh_selection_info_if_selected()
		return
	if manager.has_method("get_upgrade_building_id") and manager.get_upgrade_building_id(active_upgrade_id) != 0 and manager.get_upgrade_building_id(active_upgrade_id) != get_instance_id():
		active_upgrade_id = ""
		_refresh_selection_info_if_selected()
		return
	_refresh_info_panel_only()

func _enqueue_unit_production(unit_name_to_queue: String, _scene: PackedScene, _icon: Texture2D, _time: float, pop_cost: int, mineral_cost: int, gas_cost: int):
	if is_under_construction or production_queue.size() >= max_production_queue:
		return
	if lab_construction_active:
		_show_notice("부속건물을 건설 중입니다")
		return
	var hud = _get_hud()
	if hud:
		if hud.has_method("get_cost_failure_message"):
			var cost_message = hud.get_cost_failure_message(mineral_cost, gas_cost)
			if not cost_message.is_empty():
				hud.show_notice(cost_message)
				return
		if hud.has_method("can_reserve_population") and not hud.can_reserve_population(pop_cost):
			if hud.has_method("play_ui_alert"):
				hud.play_ui_alert("population")
			if hud.has_method("show_notice"):
				hud.show_notice("인구수가 부족합니다")
			return
		if hud.has_method("spend_resource") and not hud.spend_resource(mineral_cost, gas_cost):
			return
		if hud.has_method("reserve_population") and not hud.reserve_population(pop_cost):
			return
	production_queue.append(unit_name_to_queue)
	if production_queue.size() == 1:
		production_timer = 0.0
	_refresh_selection_info_if_selected()
	queue_redraw()

func _on_build_lab_pressed():
	if building_name != DOK_BUILDING_NAME or _has_laboratory() or lab_pending:
		return
	if not production_queue.is_empty():
		_show_notice("유닛생산중에는 건설할 수 없습니다")
		return
	lab_pending = true
	_refresh_selection_info_if_selected()
	queue_redraw()
	await get_tree().create_timer(0.2).timeout
	if not lab_pending:
		return
	if not _can_place_laboratory():
		lab_pending = false
		_play_student_voice("error")
		_show_notice("해당위치에는 건설 할 수 없습니다")
		_refresh_selection_info_if_selected()
		queue_redraw()
		return
	var hud = _get_hud()
	if hud:
		if hud.has_method("get_cost_failure_message"):
			var cost_message = hud.get_cost_failure_message(LAB_MINERAL_COST, LAB_GAS_COST)
			if not cost_message.is_empty():
				hud.show_notice(cost_message)
				lab_pending = false
				_refresh_selection_info_if_selected()
				queue_redraw()
				return
		if hud.has_method("spend_resource") and not hud.spend_resource(LAB_MINERAL_COST, LAB_GAS_COST):
			lab_pending = false
			_refresh_selection_info_if_selected()
			queue_redraw()
			return
	_begin_laboratory_construction()

func confirm_laboratory_placement() -> bool:
	if not lab_pending:
		return false
	return true

func _begin_laboratory_construction():
	lab_pending = false
	lab_pending_cost_paid = false
	lab_reserved_cells = _get_laboratory_cells()
	_mark_lab_cells_obstacle()
	lab_construction_active = true
	lab_construction_timer = 0.0
	_ensure_laboratory_site()
	_refresh_selection_info_if_selected()
	queue_redraw()

func cancel_laboratory_placement():
	if not lab_pending:
		return
	lab_pending = false
	if lab_pending_cost_paid:
		var hud = _get_hud()
		if hud and hud.has_method("add_resource"):
			hud.add_resource(LAB_MINERAL_COST, LAB_GAS_COST)
	lab_pending_cost_paid = false
	_refresh_selection_info_if_selected()
	queue_redraw()

func _process_production(delta: float):
	if is_under_construction or production_queue.is_empty():
		return
	if _is_current_lab_job():
		_process_laboratory_construction(delta)
		return
	if production_queue[0] == PROFESSOR_QUEUE_NAME and not _has_completed_laboratory():
		_refresh_info_panel_only()
		return
	var active_time := _get_current_production_time()
	production_timer += delta
	if production_timer < active_time:
		_refresh_info_panel_only()
		return
	_spawn_production_unit()
	production_queue.pop_front()
	production_timer = 0.0
	_refresh_info_panel_only()

func _process_laboratory_construction(delta: float):
	_ensure_laboratory_site()
	lab_construction_timer += delta
	if is_instance_valid(lab_site) and "construction_progress" in lab_site:
		lab_site.construction_progress = clamp(lab_construction_timer / LAB_BUILD_TIME, 0.0, 1.0)
		if "hp" in lab_site and "max_hp" in lab_site:
			lab_site.hp = max(1, int(round(lab_site.max_hp * lab_site.construction_progress)))
		lab_site.queue_redraw()
	if lab_construction_timer < LAB_BUILD_TIME:
		_refresh_info_panel_only()
		return
	if is_instance_valid(lab_site) and lab_site.has_method("complete_construction"):
		lab_site.complete_construction()
	lab_construction_active = false
	lab_construction_timer = 0.0
	lab_pending_cost_paid = false
	_refresh_selection_info_if_selected()

func _update_production_sprite(delta: float):
	var normal_texture := _get_activity_normal_texture()
	var on_texture := _get_activity_on_texture()
	if not normal_texture or not on_texture:
		return
	var sprite = get_node_or_null("Sprite2D")
	if not sprite or not sprite is Sprite2D or not sprite.visible:
		return
	if is_under_construction or (production_queue.is_empty() and active_upgrade_id.is_empty()):
		production_sprite_timer = 0.0
		production_sprite_on = false
		if sprite.texture != normal_texture:
			sprite.texture = normal_texture
		return
	production_sprite_timer += delta
	if production_sprite_timer < PRODUCTION_SPRITE_INTERVAL:
		return
	production_sprite_timer = 0.0
	production_sprite_on = not production_sprite_on
	sprite.texture = on_texture if production_sprite_on else normal_texture

func _get_activity_normal_texture() -> Texture2D:
	if building_name == MUSEUM_BUILDING_NAME:
		return MUSEUM_TEXTURE
	if building_name == DOK_BUILDING_NAME:
		return DOK_TEXTURE
	if building_name == LAB_BUILDING_NAME:
		return LAB_TEXTURE
	return null

func _get_activity_on_texture() -> Texture2D:
	if building_name == MUSEUM_BUILDING_NAME:
		return MUSEUM_ON_TEXTURE
	if building_name == DOK_BUILDING_NAME:
		return DOK_ON_TEXTURE
	if building_name == LAB_BUILDING_NAME:
		return LAB_ON_TEXTURE
	return null

func _spawn_student():
	_spawn_production_unit()

func _spawn_production_unit():
	if _is_current_lab_job():
		return
	var scene = _get_queue_scene(production_queue[0])
	if not scene:
		return
	var parent = get_tree().current_scene.find_child("Units", true, false) if get_tree().current_scene else null
	if not parent:
		parent = get_parent()
	var produced_unit = scene.instantiate()
	parent.add_child(produced_unit)
	if produced_unit is Node2D:
		produced_unit.global_position = _get_production_spawn_position()
		_apply_rally_order(produced_unit)
		var manager = get_tree().get_first_node_in_group("UnitManager")
		if manager and manager.has_method("is_student_unit") and manager.is_student_unit(produced_unit) and manager.has_method("play_student_voice"):
			manager.play_student_voice("ready", produced_unit)
		if manager and manager.has_method("is_graduate_unit") and manager.is_graduate_unit(produced_unit) and manager.has_method("play_graduate_voice"):
			manager.play_graduate_voice("ready", produced_unit)
		if manager and manager.has_method("is_professor_unit") and manager.is_professor_unit(produced_unit) and manager.has_method("play_professor_voice"):
			manager.play_professor_voice("ready", produced_unit)
		if manager and manager.has_method("is_armi_unit") and manager.is_armi_unit(produced_unit) and manager.has_method("play_armi_voice"):
			manager.play_armi_voice("ready", produced_unit)

func set_rally_point(pos: Vector2):
	if not can_set_rally_point():
		return
	rally_position = pos
	rally_resource = null
	has_rally_point = true
	queue_redraw()

func set_rally_resource(resource: Node2D):
	if not can_set_rally_point():
		return
	if not is_instance_valid(resource):
		return
	rally_resource = resource
	rally_position = resource.global_position
	has_rally_point = true
	queue_redraw()

func can_set_rally_point() -> bool:
	return not is_under_construction and can_produce_units

func _apply_rally_order(student: Node2D):
	if is_instance_valid(rally_resource) and student.has_method("start_gathering") and "can_gather" in student and student.can_gather:
		student.start_gathering(rally_resource)
	elif is_instance_valid(rally_resource) and student.has_method("set_target"):
		student.set_target(rally_resource.global_position)
	elif has_rally_point and student.has_method("set_target"):
		student.set_target(rally_position)

func _get_production_spawn_position() -> Vector2:
	var tile_map = _get_placement_tile_map()
	if tile_map and not occupied_cells.is_empty():
		var spawn_cell = _find_spawn_cell(tile_map)
		if spawn_cell != null:
			return tile_map.to_global(tile_map.map_to_local(spawn_cell))
	var rect := get_rect()
	return Vector2(rect.position.x + rect.size.x * 0.5, rect.position.y + rect.size.y + 48.0)

func _get_placement_tile_map():
	if not placement_controller:
		placement_controller = get_tree().get_first_node_in_group("BuildingPlacement")
	if placement_controller and "tile_map" in placement_controller:
		return placement_controller.tile_map
	return null

func _find_spawn_cell(tile_map) -> Variant:
	var min_cell: Vector2i = occupied_cells[0]
	var max_cell: Vector2i = occupied_cells[0]
	for cell in occupied_cells:
		min_cell.x = mini(min_cell.x, cell.x)
		min_cell.y = mini(min_cell.y, cell.y)
		max_cell.x = maxi(max_cell.x, cell.x)
		max_cell.y = maxi(max_cell.y, cell.y)
	var center_x := int(round((min_cell.x + max_cell.x) * 0.5))
	for row_distance in range(1, 9):
		for x_offset in range(0, 8):
			var below_left := Vector2i(center_x - x_offset, max_cell.y + row_distance)
			if _is_spawn_cell_open(tile_map, below_left):
				return below_left
			var below_right := Vector2i(center_x + x_offset, max_cell.y + row_distance)
			if _is_spawn_cell_open(tile_map, below_right):
				return below_right
	for side_distance in range(1, 8):
		var side_left := Vector2i(min_cell.x - side_distance, max_cell.y)
		if _is_spawn_cell_open(tile_map, side_left):
			return side_left
		var side_right := Vector2i(max_cell.x + side_distance, max_cell.y)
		if _is_spawn_cell_open(tile_map, side_right):
			return side_right
	return null

func _is_spawn_cell_open(tile_map, cell: Vector2i) -> bool:
	if tile_map.get_cell_source_id(cell) != EMPTY_TILE_SOURCE_ID:
		return false
	for unit in get_tree().get_nodes_in_group("Unit"):
		if is_instance_valid(unit) and unit is Node2D:
			var unit_cell = tile_map.local_to_map(tile_map.to_local(unit.global_position))
			if unit_cell == cell:
				return false
	return true

func _is_current_lab_job() -> bool:
	return not production_queue.is_empty() and production_queue[0] == LAB_QUEUE_NAME

func _has_laboratory() -> bool:
	if lab_pending or lab_construction_active or production_queue.has(LAB_QUEUE_NAME):
		return true
	return is_instance_valid(lab_site)

func _has_completed_laboratory() -> bool:
	return is_instance_valid(lab_site) and (not ("is_under_construction" in lab_site) or not lab_site.is_under_construction)

func has_completed_laboratory() -> bool:
	return _has_completed_laboratory()

func _has_completed_building(target_building_name: String) -> bool:
	for building in get_tree().get_nodes_in_group("Building"):
		if not is_instance_valid(building) or not ("building_name" in building):
			continue
		if str(building.building_name).strip_edges() != target_building_name:
			continue
		if not ("is_under_construction" in building) or not building.is_under_construction:
			return true
	return false

func is_waiting_for_laboratory_placement() -> bool:
	return lab_pending

func _can_place_laboratory() -> bool:
	var tile_map = _get_placement_tile_map()
	if not tile_map:
		return false
	var cells := _get_laboratory_cells()
	if cells.is_empty():
		return false
	for cell in cells:
		if not _is_lab_cell_buildable(tile_map, cell):
			return false
	return true

func _get_laboratory_cells() -> Array[Vector2i]:
	var base_cells := _get_current_occupied_cells()
	if base_cells.is_empty():
		return []
	var min_cell: Vector2i = base_cells[0]
	var max_cell: Vector2i = base_cells[0]
	for cell in base_cells:
		min_cell.x = mini(min_cell.x, cell.x)
		min_cell.y = mini(min_cell.y, cell.y)
		max_cell.x = maxi(max_cell.x, cell.x)
		max_cell.y = maxi(max_cell.y, cell.y)
	var origin := Vector2i(max_cell.x + 1, max_cell.y - LAB_FOOTPRINT_TILES.y + 1)
	var cells: Array[Vector2i] = []
	for y in range(LAB_FOOTPRINT_TILES.y):
		for x in range(LAB_FOOTPRINT_TILES.x):
			cells.append(origin + Vector2i(x, y))
	return cells

func _get_current_occupied_cells() -> Array[Vector2i]:
	if not occupied_cells.is_empty():
		return occupied_cells
	var tile_map = _get_placement_tile_map()
	if not tile_map:
		return []
	var local_pos = tile_map.to_local(global_position)
	local_pos.y -= footprint_tiles.y * tile_size * 0.5
	var center_cell = tile_map.local_to_map(local_pos)
	var origin = center_cell - Vector2i(floori(footprint_tiles.x / 2.0), floori(footprint_tiles.y / 2.0))
	var cells: Array[Vector2i] = []
	for y in range(footprint_tiles.y):
		for x in range(footprint_tiles.x):
			cells.append(origin + Vector2i(x, y))
	return cells

func _is_lab_cell_buildable(tile_map, cell: Vector2i) -> bool:
	if tile_map.get_cell_source_id(cell) != EMPTY_TILE_SOURCE_ID:
		return false
	var data = tile_map.get_cell_tile_data(cell)
	return data != null and data.get_custom_data("can_build") == true

func _mark_lab_cells_obstacle():
	if not placement_controller:
		placement_controller = get_tree().get_first_node_in_group("BuildingPlacement")
	if placement_controller and placement_controller.has_method("_set_cells_obstacle"):
		placement_controller._set_cells_obstacle(lab_reserved_cells)

func _ensure_laboratory_site():
	if not placement_controller:
		placement_controller = get_tree().get_first_node_in_group("BuildingPlacement")
	if is_instance_valid(lab_site) or not placement_controller or lab_reserved_cells.is_empty():
		return
	var center := _get_cells_bottom_center(lab_reserved_cells)
	var config := {
		"building_name": LAB_BUILDING_NAME,
		"description": "덕래관의 연구실이다",
		"can_produce_students": false,
		"can_produce_units": false,
		"supply_bonus": 0,
		"accepts_resource_dropoff": false,
		"max_hp": 500,
		"build_time": LAB_BUILD_TIME,
		"footprint_tiles": LAB_FOOTPRINT_TILES,
		"visual_ground_ratio": 0.8,
		"visual_scale_override": LAB_VISUAL_SCALE,
		"icon_texture": LAB_BUTTON_TEXTURE,
		"mineral_cost": LAB_MINERAL_COST,
		"gas_cost": LAB_GAS_COST
	}
	if placement_controller.has_method("create_construction_site"):
		lab_site = placement_controller.create_construction_site(center, null, lab_reserved_cells, config)
		if is_instance_valid(lab_site):
			lab_site.set_meta("owner_building_id", get_instance_id())
			if lab_site.has_method("set_waiting_for_builder"):
				lab_site.set_waiting_for_builder(false)
			if "builder" in lab_site:
				lab_site.builder = self

func _on_laboratory_destroyed(site: Node2D):
	if site == lab_site:
		lab_site = null
		lab_construction_active = false
		lab_construction_timer = 0.0
		lab_reserved_cells.clear()
	_refresh_selection_info_if_selected()

func _get_cells_bottom_center(cells: Array[Vector2i]) -> Vector2:
	if placement_controller and placement_controller.has_method("_cells_bottom_center"):
		return placement_controller._cells_bottom_center(cells)
	var tile_map = _get_placement_tile_map()
	if not tile_map or cells.is_empty():
		return global_position
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

func _show_notice(text: String):
	var hud = _get_hud()
	if hud and hud.has_method("show_notice"):
		hud.show_notice(text)

func _play_student_voice(voice_type: String):
	var manager = get_tree().get_first_node_in_group("UnitManager")
	if manager and manager.has_method("play_student_voice"):
		manager.play_student_voice(voice_type)

func _get_current_production_time() -> float:
	if production_queue.is_empty():
		return _get_display_production_time(production_time)
	var item := production_queue[0]
	if item == LAB_QUEUE_NAME:
		return LAB_BUILD_TIME
	if item == PROFESSOR_QUEUE_NAME:
		return _get_display_production_time(PROFESSOR_PRODUCTION_TIME)
	if item == ARMI_QUEUE_NAME:
		return _get_display_production_time(ARMI_PRODUCTION_TIME)
	return _get_display_production_time(production_time)

func _get_display_production_time(base_time: float) -> float:
	return 1.0 if _is_test_mode_enabled() else base_time

func _is_test_mode_enabled() -> bool:
	return get_tree().root.has_meta("test_mode") and bool(get_tree().root.get_meta("test_mode"))

func _get_queue_scene(item: String) -> PackedScene:
	if item == PROFESSOR_QUEUE_NAME:
		return PROFESSOR_SCENE
	if item == ARMI_QUEUE_NAME:
		return ARMI_SCENE
	return production_unit_scene if production_unit_scene else student_scene

func _get_queue_icon(item: String) -> Texture2D:
	if item == LAB_QUEUE_NAME:
		return LAB_BUTTON_TEXTURE
	if item == PROFESSOR_QUEUE_NAME:
		return PROFESSOR_ICON
	if item == ARMI_QUEUE_NAME:
		return ARMI_ICON
	return production_unit_icon

func _get_queue_population_cost(item: String) -> int:
	if item == PROFESSOR_QUEUE_NAME:
		return PROFESSOR_POPULATION_COST
	if item == ARMI_QUEUE_NAME:
		return ARMI_POPULATION_COST
	if item == LAB_QUEUE_NAME:
		return 0
	return production_population_cost

func _get_queue_mineral_cost(item: String) -> int:
	if item == PROFESSOR_QUEUE_NAME:
		return PROFESSOR_MINERAL_COST
	if item == ARMI_QUEUE_NAME:
		return ARMI_MINERAL_COST
	if item == LAB_QUEUE_NAME:
		return LAB_MINERAL_COST
	return production_mineral_cost

func _get_queue_gas_cost(item: String) -> int:
	if item == PROFESSOR_QUEUE_NAME:
		return PROFESSOR_GAS_COST
	if item == ARMI_QUEUE_NAME:
		return ARMI_GAS_COST
	if item == LAB_QUEUE_NAME:
		return LAB_GAS_COST
	return production_gas_cost

func get_production_queue_size() -> int:
	return production_queue.size()

func get_unit_production_queue_size() -> int:
	return production_queue.size()

func get_current_production_icon() -> Texture2D:
	if lab_construction_active:
		return LAB_BUTTON_TEXTURE
	if production_queue.is_empty():
		return null
	return _get_queue_icon(production_queue[0])

func can_accept_button_command(function_name: String) -> bool:
	var upgrade_id := _get_upgrade_id_for_function(function_name)
	if not upgrade_id.is_empty():
		if not active_upgrade_id.is_empty():
			return false
		if _is_training_upgrade(upgrade_id) and not _is_training_building():
			return false
		if _is_trait_upgrade(upgrade_id) and not _is_laboratory_building():
			return false
		var manager = get_tree().get_first_node_in_group("UnitManager")
		if manager and manager.has_method("can_start_upgrade_for_building"):
			return manager.can_start_upgrade_for_building(upgrade_id, get_instance_id())
		return manager and manager.has_method("can_start_upgrade") and manager.can_start_upgrade(upgrade_id)
	if function_name == "_on_train_unit_pressed" or function_name == "_on_train_professor_pressed" or function_name == "_on_train_armi_pressed":
		if lab_construction_active:
			return false
		if is_under_construction or production_queue.size() >= max_production_queue:
			return false
		if function_name == "_on_train_unit_pressed":
			return can_produce_units
		if building_name != DOK_BUILDING_NAME:
			return false
		if function_name == "_on_train_professor_pressed":
			return _has_completed_laboratory()
		if function_name == "_on_train_armi_pressed":
			return _has_completed_building(TRAINING_BUILDING_NAME)
	if is_under_construction:
		return false
	if function_name == "_on_build_lab_pressed":
		return building_name == DOK_BUILDING_NAME and not _has_laboratory() and production_queue.is_empty() and _can_place_laboratory()
	return false

func get_button_command_block_message(function_name: String) -> String:
	var upgrade_id := _get_upgrade_id_for_function(function_name)
	if not upgrade_id.is_empty():
		var manager = get_tree().get_first_node_in_group("UnitManager")
		if manager and manager.has_method("is_upgrade_in_progress") and manager.is_upgrade_in_progress(upgrade_id):
			return "이미 같은 강화가 진행 중입니다"
		return "더 이상 강화할 수 없습니다"
	if function_name == "_on_build_lab_pressed":
		if building_name != DOK_BUILDING_NAME:
			return ""
		if _has_laboratory():
			return "이미 연구실이 있습니다"
		if not production_queue.is_empty():
			return "유닛생산중에는 건설할 수 없습니다"
		if not _can_place_laboratory():
			return "해당위치에는 건설 할 수 없습니다"
	if function_name == "_on_train_unit_pressed" or function_name == "_on_train_professor_pressed" or function_name == "_on_train_armi_pressed":
		if lab_construction_active:
			return "부속건물을 건설 중입니다"
		if production_queue.size() >= max_production_queue:
			return "생산 대기열이 가득 찼습니다"
		if function_name == "_on_train_professor_pressed" and not _has_completed_laboratory():
			return "연구실이 필요합니다"
		if function_name == "_on_train_armi_pressed" and not _has_completed_building(TRAINING_BUILDING_NAME):
			return "훈련소가 필요합니다"
	return ""

func _get_upgrade_id_for_function(function_name: String) -> String:
	match function_name:
		"_on_upgrade_body_pressed":
			return "body"
		"_on_upgrade_power_pressed":
			return "power"
		"_on_upgrade_student_trait_pressed":
			return "student"
		"_on_upgrade_m_student_trait_pressed":
			return "m_student"
		"_on_upgrade_professor_trait_pressed":
			return "professor"
		"_on_upgrade_armi_trait_pressed":
			return "armi"
	return ""

func _is_training_upgrade(upgrade_id: String) -> bool:
	return upgrade_id == "body" or upgrade_id == "power"

func _is_trait_upgrade(upgrade_id: String) -> bool:
	return not _is_training_upgrade(upgrade_id)

func cancel_production_at_index(index: int) -> bool:
	if index < 0 or index >= production_queue.size():
		return false
	var item := production_queue[index]
	production_queue.remove_at(index)
	if index == 0:
		production_timer = 0.0
	var hud = _get_hud()
	if hud:
		var pop_cost := _get_queue_population_cost(item)
		if pop_cost > 0 and hud.has_method("release_population"):
			hud.release_population(pop_cost)
		if hud.has_method("add_resource"):
			hud.add_resource(_get_queue_mineral_cost(item), _get_queue_gas_cost(item))
	_refresh_selection_info_if_selected()
	queue_redraw()
	return true

func get_production_progress() -> float:
	if lab_construction_active:
		return clamp(lab_construction_timer / max(LAB_BUILD_TIME, 0.01), 0.0, 1.0)
	if production_queue.is_empty():
		return 0.0
	var active_time := _get_current_production_time()
	return clamp(production_timer / max(active_time, 0.01), 0.0, 1.0)

func get_production_queue_textures() -> Array:
	if lab_construction_active:
		return [LAB_BUTTON_TEXTURE]
	var textures: Array = []
	for item in production_queue:
		textures.append(_get_queue_icon(item))
	return textures

func get_production_status_text() -> String:
	if lab_construction_active:
		return "연구실 건설중"
	if production_queue.is_empty():
		return ""
	return str(production_queue[0])

func has_active_upgrade() -> bool:
	return not active_upgrade_id.is_empty()

func get_upgrade_progress() -> float:
	if active_upgrade_id.is_empty():
		return 0.0
	var manager = get_tree().get_first_node_in_group("UnitManager")
	if manager and manager.has_method("get_upgrade_progress"):
		return manager.get_upgrade_progress(active_upgrade_id)
	return 0.0

func get_upgrade_queue_textures() -> Array:
	var icon := _get_active_upgrade_icon()
	return [icon] if icon else []

func get_upgrade_status_text() -> String:
	if active_upgrade_id.is_empty():
		return ""
	var manager = get_tree().get_first_node_in_group("UnitManager")
	if manager and manager.has_method("get_upgrade_display_name"):
		return "%s 진행중" % manager.get_upgrade_display_name(active_upgrade_id)
	return "강화 진행중"

func _get_active_upgrade_icon() -> Texture2D:
	var manager = get_tree().get_first_node_in_group("UnitManager")
	if manager and manager.has_method("get_upgrade_icon_path"):
		return load(manager.get_upgrade_icon_path(active_upgrade_id))
	return null

func add_construction_progress(delta: float, building_builder: Node2D):
	if not is_under_construction or not is_instance_valid(building_builder):
		return
	if not is_instance_valid(builder):
		builder = building_builder
	construction_started = true
	set_waiting_for_builder(false)
	_advance_construction(delta)

func _process_construction(delta: float):
	if not is_under_construction or waiting_for_builder or not construction_started:
		return
	if not is_instance_valid(builder):
		return
	_advance_construction(delta)

func _advance_construction(delta: float):
	var current_frame := Engine.get_process_frames()
	if last_construction_progress_frame == current_frame:
		return
	last_construction_progress_frame = current_frame
	construction_progress = clamp(construction_progress + (delta / max(build_time, 0.01)), 0.0, 1.0)
	hp = max(1, int(round(max_hp * construction_progress)))
	if construction_progress >= 1.0:
		complete_construction()
	queue_redraw()
	_refresh_selection_info_if_selected()

func start_construction(building_builder: Node2D = null, cells: Array = [], placement: Node = null):
	builder = building_builder
	occupied_cells = cells.duplicate()
	placement_controller = placement
	if is_instance_valid(foundation_node):
		global_position = _get_bottom_center_from_foundation()
		if "resource_amount" in foundation_node:
			resource_amount = foundation_node.resource_amount
		if foundation_node.has_method("get_max_resource_amount"):
			max_resource_amount = foundation_node.get_max_resource_amount()
		if foundation_node.has_method("set_used"):
			foundation_node.set_used(true)
	is_under_construction = true
	waiting_for_builder = not is_instance_valid(builder)
	construction_started = false
	construction_progress = 0.0
	last_construction_progress_frame = -1
	hp = 1
	set_waiting_for_builder(waiting_for_builder)
	if is_in_group("ResourceDropoff"):
		remove_from_group("ResourceDropoff")
	if is_in_group("ResourceDeposit"):
		remove_from_group("ResourceDeposit")
	queue_redraw()

func set_waiting_for_builder(is_waiting: bool):
	waiting_for_builder = is_waiting
	modulate = Color(1, 1, 1, 0.45) if waiting_for_builder else Color.WHITE
	if not waiting_for_builder:
		reserved_builder = null
		reservation_required = false
	if waiting_for_builder and is_instance_valid(builder):
		builder = null
	queue_redraw()

func begin_reserved_construction(building_builder: Node2D):
	if not is_instance_valid(building_builder):
		return
	builder = building_builder
	waiting_for_builder = false
	reserved_builder = null
	reservation_required = false
	construction_started = true
	modulate = Color.WHITE
	queue_redraw()

func set_reserved_builder(unit: Node2D):
	reserved_builder = unit if is_instance_valid(unit) else null
	reservation_required = is_instance_valid(reserved_builder)

func can_be_built_by(unit: Node2D) -> bool:
	if not is_under_construction or not is_instance_valid(unit):
		return false
	return true

func pause_construction(building_builder: Node2D = null):
	if is_instance_valid(building_builder) and builder == building_builder:
		builder = null
	reserved_builder = null
	reservation_required = false
	if construction_started or construction_progress > 0.0:
		waiting_for_builder = false
		modulate = Color.WHITE
		queue_redraw()
	else:
		set_waiting_for_builder(true)

func complete_construction():
	var completed_builder = builder
	is_under_construction = false
	waiting_for_builder = false
	construction_started = false
	last_construction_progress_frame = -1
	modulate = Color.WHITE
	construction_progress = 1.0
	hp = max_hp
	_refresh_resource_dropoff_group()
	_refresh_resource_deposit_group()
	_apply_supply_bonus()
	_refresh_selection_info_if_selected()
	var manager = get_tree().get_first_node_in_group("UnitManager")
	if is_instance_valid(completed_builder) and completed_builder.has_method("on_construction_completed"):
		completed_builder.on_construction_completed(self)
	if manager and manager.has_method("is_student_unit") and manager.is_student_unit(completed_builder) and manager.has_method("play_student_voice"):
		manager.play_student_voice("complete", completed_builder)

func cancel_construction():
	_destroy()

func take_damage(amount: int, source = null):
	if is_in_group("Ally") and (not is_instance_valid(source) or source.is_in_group("Enemy")):
		var manager = get_tree().get_first_node_in_group("UnitManager")
		if manager and manager.has_method("notify_ally_under_attack"):
			manager.notify_ally_under_attack(self, "building")
	hp -= amount

func play_bullet_hit_effect():
	var now := Time.get_ticks_msec()
	if now - last_bullet_hit_effect_msec < 80:
		return
	last_bullet_hit_effect_msec = now
	var particles := CPUParticles2D.new()
	particles.name = "BulletHitEffect"
	particles.amount = 32
	particles.one_shot = true
	particles.lifetime = 0.5
	particles.explosiveness = 0.95
	particles.randomness = 0.8
	particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	particles.emission_sphere_radius = 11.0
	particles.direction = Vector2(0, -1)
	particles.spread = 170.0
	particles.initial_velocity_min = 30.0
	particles.initial_velocity_max = 82.0
	particles.gravity = Vector2(0, 34.0)
	particles.scale_amount_min = 3.4
	particles.scale_amount_max = 6.4
	particles.color = Color(1.0, 0.72, 0.0, 1.0)
	var size := _get_footprint_size()
	particles.position = Vector2(0, -max(24.0, size.y * 0.45))
	particles.z_index = 21
	add_child(particles)
	particles.emitting = true
	await get_tree().create_timer(0.8).timeout
	if is_instance_valid(particles):
		particles.queue_free()

func take_resource(amount: int) -> int:
	if not provides_resource or is_under_construction or resource_amount <= 0:
		return 0
	var mined = min(amount, resource_amount)
	if is_instance_valid(foundation_node) and foundation_node.has_method("consume_resource"):
		mined = foundation_node.consume_resource(amount)
	resource_amount = max(0, resource_amount - mined)
	if resource_amount <= 0:
		_destroy()
	else:
		queue_redraw()
		_refresh_selection_info_if_selected()
	return mined

func is_depleted() -> bool:
	return provides_resource and resource_amount <= 0

func get_resource_kind() -> String:
	return resource_kind

func get_gather_time() -> float:
	return gather_time_override if gather_time_override > 0.0 else 0.0

func get_max_resource_amount() -> int:
	return max(max_resource_amount, resource_amount)

func _destroy():
	_release_gatherers_before_destroy()
	if building_name == LAB_BUILDING_NAME and has_meta("owner_building_id"):
		var owner_building = instance_from_id(int(get_meta("owner_building_id")))
		if is_instance_valid(owner_building) and owner_building.has_method("_on_laboratory_destroyed"):
			owner_building._on_laboratory_destroyed(self)
	_clear_selection_if_selected()
	_release_queued_population()
	_remove_supply_bonus()
	if is_instance_valid(foundation_node) and foundation_node.has_method("set_used"):
		if not foundation_node.has_method("is_depleted") or not foundation_node.is_depleted():
			foundation_node.set_used(false)
	if placement_controller and placement_controller.has_method("clear_build_cells"):
		placement_controller.clear_build_cells(occupied_cells)
	if is_instance_valid(foundation_node) and placement_controller and placement_controller.has_method("mark_node_obstacle"):
		if not foundation_node.has_method("is_depleted") or not foundation_node.is_depleted():
			placement_controller.mark_node_obstacle(foundation_node)
	_refresh_command_ui_deferred()
	queue_free()

func _release_gatherers_before_destroy():
	if not provides_resource:
		return
	for unit in get_tree().get_nodes_in_group("Unit"):
		if is_instance_valid(unit) and unit.has_method("release_from_depleted_resource"):
			unit.release_from_depleted_resource(self)

func get_footprint_tiles() -> Vector2i:
	return footprint_tiles

func get_rect() -> Rect2:
	var rect: Rect2 = _get_local_contact_rect()
	return Rect2(global_position + rect.position, rect.size)

func get_dropoff_rect() -> Rect2:
	var rect: Rect2 = _get_local_dropoff_rect()
	return Rect2(global_position + rect.position, rect.size)

func set_hover(is_hover: bool):
	if hover_mode == is_hover:
		return
	hover_mode = is_hover
	_update_selection_ring()

func select():
	select_mode = true
	_update_selection_ring()
	queue_redraw()

func deselect():
	cancel_laboratory_placement()
	select_mode = false
	_update_selection_ring()
	queue_redraw()

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

func _refresh_info_panel_only():
	if not select_mode:
		return
	var info_panel = get_tree().current_scene.find_child("InfoPanel", true, false) if get_tree().current_scene else null
	if info_panel and info_panel.has_method("display_units"):
		var manager = get_tree().get_first_node_in_group("UnitManager")
		if manager and "unit_selected" in manager and manager.unit_selected.size() > 1:
			info_panel.display_units(manager.unit_selected)
		else:
			info_panel.display_units([self])

func _refresh_command_ui_deferred():
	var manager = get_tree().get_first_node_in_group("UnitManager")
	if manager and manager.has_method("_refresh_command_ui"):
		manager.call_deferred("_refresh_command_ui")

func _get_hud():
	return get_tree().current_scene.find_child("HUD", true, false) if get_tree().current_scene else null

func _apply_supply_bonus():
	if supply_applied or supply_bonus <= 0:
		return
	var hud = _get_hud()
	if hud and hud.has_method("add_max_population"):
		hud.add_max_population(supply_bonus)
		supply_applied = true

func _remove_supply_bonus():
	if not supply_applied or supply_bonus <= 0:
		return
	var hud = _get_hud()
	if hud and hud.has_method("remove_max_population"):
		hud.remove_max_population(supply_bonus)
	supply_applied = false

func _release_queued_population():
	if production_queue.is_empty():
		return
	var hud = _get_hud()
	if hud and hud.has_method("release_population"):
		var unit_count := 0
		for item in production_queue:
			if item != LAB_QUEUE_NAME:
				unit_count += _get_queue_population_cost(item)
		hud.release_population(unit_count)
	if hud and hud.has_method("add_resource"):
		var lab_count := 0
		for item in production_queue:
			if item == LAB_QUEUE_NAME:
				lab_count += 1
		if lab_pending_cost_paid:
			lab_count += 1
		if lab_count > 0:
			hud.add_resource(lab_count * LAB_MINERAL_COST, lab_count * LAB_GAS_COST)
	if placement_controller and placement_controller.has_method("clear_build_cells") and not lab_reserved_cells.is_empty():
		placement_controller.clear_build_cells(lab_reserved_cells)
	production_queue.clear()
	lab_reserved_cells.clear()

func _refresh_resource_dropoff_group():
	if accepts_resource_dropoff and not is_under_construction:
		if not is_in_group("ResourceDropoff"):
			add_to_group("ResourceDropoff")
	elif is_in_group("ResourceDropoff"):
		remove_from_group("ResourceDropoff")

func _refresh_resource_deposit_group():
	if provides_resource and not is_under_construction and resource_amount > 0:
		if not is_in_group("ResourceDeposit"):
			add_to_group("ResourceDeposit")
	elif is_in_group("ResourceDeposit"):
		remove_from_group("ResourceDeposit")

func _clear_selection_if_selected():
	if not select_mode:
		return
	var manager = get_tree().get_first_node_in_group("UnitManager")
	if manager and manager.has_method("_clear_selection"):
		manager._clear_selection()

func _create_selection_ring():
	var size = _get_footprint_size()
	selection_ring = Node2D.new()
	selection_ring.set_script(SELECTION_RING_SCRIPT)
	selection_ring.radius = size.x * 0.58
	selection_ring.ellipse_scale = Vector2(1.0, max(0.34, size.y / max(size.x, 1.0) * 0.6))
	selection_ring.offset = Vector2(0, -size.y * 0.18)
	selection_ring.hover_color = Color(1.0, 0.95, 0.0, 1.0)
	selection_ring.selected_color = Color(0.0, 1.0, 0.0, 0.9)
	selection_ring.visible = false
	add_child(selection_ring)

func _configure_visual_sprite():
	var sprite = get_node_or_null("Sprite2D")
	if not sprite or not sprite is Sprite2D:
		return
	var building_texture = _get_building_texture()
	sprite.visible = building_texture != null
	if not sprite.visible:
		return
	sprite.texture = building_texture
	sprite.centered = true
	var ratio = clamp(visual_ground_ratio, 0.1, 1.0)
	var base_height = footprint_tiles.y * tile_size
	var footprint_size = Vector2(footprint_tiles * tile_size)
	var scale_factor = base_height / max(sprite.texture.get_height() * ratio, 1.0)
	if visual_scale_override > 0.0:
		scale_factor = visual_scale_override
	if lock_footprint_to_config:
		scale_factor = min(
			footprint_size.x / max(sprite.texture.get_width(), 1.0),
			footprint_size.y / max(sprite.texture.get_height(), 1.0)
		)
	sprite.scale = Vector2(scale_factor, scale_factor)
	var visual_size = sprite.texture.get_size() * scale_factor
	if not lock_footprint_to_config:
		footprint_tiles = Vector2i(
			ceili(visual_size.x / float(tile_size)),
			ceili((visual_size.y * ratio) / float(tile_size))
		)
	_update_collision_shape()
	var visual_height = visual_size.y
	sprite.position = Vector2(0.0, -visual_height * 0.5)
	sprite.z_index = -1

func _get_building_texture() -> Texture2D:
	if building_name == MUSEUM_BUILDING_NAME:
		return MUSEUM_TEXTURE
	if building_name == RESTAURANT_BUILDING_NAME:
		return RESTAURANT_TEXTURE
	if building_name == DOK_BUILDING_NAME:
		return DOK_TEXTURE
	if building_name == LAB_BUILDING_NAME:
		return LAB_TEXTURE
	if building_name == EXCAVATION_BUILDING_NAME:
		return EXCAVATION_TEXTURE
	if str(building_name).strip_edges() == str(TRAINING_BUILDING_NAME).strip_edges():
		return TRAINING_TEXTURE
	return icon_texture

func _get_bottom_center_from_foundation() -> Vector2:
	if not is_instance_valid(foundation_node):
		return global_position
	if foundation_node.has_method("get_rect"):
		var rect: Rect2 = foundation_node.get_rect()
		return Vector2(rect.position.x + rect.size.x * 0.5, rect.position.y + rect.size.y)
	var size = Vector2(footprint_tiles * tile_size)
	return foundation_node.global_position + Vector2(0.0, size.y * 0.5)

func _update_collision_shape():
	var collision_shape = get_node_or_null("CollisionShape2D")
	if not collision_shape or not collision_shape is CollisionShape2D:
		return
	var rect_shape = collision_shape.shape
	if not rect_shape or not rect_shape is RectangleShape2D:
		rect_shape = RectangleShape2D.new()
		collision_shape.shape = rect_shape
	var rect: Rect2 = _get_local_contact_rect()
	rect_shape.size = rect.size
	collision_shape.position = rect.position + rect.size * 0.5

func _has_visual_sprite() -> bool:
	var sprite = get_node_or_null("Sprite2D")
	return sprite and sprite is Sprite2D and sprite.visible and sprite.texture

func _get_footprint_size() -> Vector2:
	return Vector2(footprint_tiles * tile_size)

func _get_local_contact_rect() -> Rect2:
	var size: Vector2 = _get_footprint_size()
	var height: float = maxf(16.0, size.y * CONTACT_HEIGHT_RATIO)
	return Rect2(Vector2(-size.x * 0.5, -height), Vector2(size.x, height))

func _get_local_dropoff_rect() -> Rect2:
	var size: Vector2 = _get_footprint_size()
	var height: float = maxf(16.0, size.y * DROPOFF_TOP_HEIGHT_RATIO)
	var contact_rect: Rect2 = _get_local_contact_rect()
	var center_y: float = contact_rect.position.y + contact_rect.size.y * 0.5
	return Rect2(Vector2(-size.x * 0.5, center_y - height * 0.5), Vector2(size.x, height))

func _get_visual_size() -> Vector2:
	var sprite = get_node_or_null("Sprite2D")
	if sprite and sprite is Sprite2D and sprite.visible and sprite.texture:
		return sprite.texture.get_size() * sprite.scale
	return _get_footprint_size()

func _get_visual_rect() -> Rect2:
	var sprite = get_node_or_null("Sprite2D")
	if sprite and sprite is Sprite2D and sprite.visible and sprite.texture:
		var visual_size = sprite.texture.get_size() * sprite.scale
		return Rect2(sprite.position - (visual_size * 0.5), visual_size)
	var size = _get_footprint_size()
	return Rect2(-size * 0.5, size)

func _update_selection_ring():
	if selection_ring:
		selection_ring.set_modes(hover_mode, select_mode)

func _draw():
	var size = _get_footprint_size()
	var rect = Rect2(Vector2(-size.x * 0.5, -size.y), size)
	if _has_visual_sprite():
		if is_under_construction:
			var tint_color = Color(0.35, 0.20, 0.18, 0.28).lerp(Color(0.20, 0.38, 0.24, 0.22), construction_progress)
			draw_rect(rect, tint_color, true)
			draw_rect(rect, Color(0.82, 0.88, 0.9, 0.65), false, 2.0)
			_draw_construction_bands()
	else:
		var body_color = Color(0.24, 0.25, 0.28, 0.95)
		if is_under_construction:
			body_color = Color(0.35, 0.20, 0.18, 0.75).lerp(Color(0.20, 0.38, 0.24, 0.95), construction_progress)
		draw_rect(rect, body_color, true)
		draw_rect(rect, Color(0.82, 0.88, 0.9), false, 2.0)
		draw_rect(Rect2(-18, -12, 36, 28), Color(0.11, 0.12, 0.15), true)
		draw_rect(Rect2(-18, -12, 36, 28), Color(0.82, 0.88, 0.9), false, 1.0)
	if is_under_construction:
		var bar_rect = Rect2(Vector2(-size.x * 0.45, 12), Vector2(size.x * 0.9, 6))
		draw_rect(bar_rect, Color(0.05, 0.05, 0.05, 0.85), true)
		draw_rect(Rect2(bar_rect.position, Vector2(bar_rect.size.x * construction_progress, bar_rect.size.y)), Color.RED.lerp(Color.GREEN, construction_progress), true)
		draw_rect(bar_rect, Color.BLACK, false, 1.0)
	elif max_hp > 0 and (select_mode or hp < max_hp):
		var hp_ratio = clamp(float(hp) / float(max_hp), 0.0, 1.0)
		var bar_rect = Rect2(Vector2(-size.x * 0.45, 12), Vector2(size.x * 0.9, 6))
		draw_rect(bar_rect, Color.WHITE, true)
		draw_rect(Rect2(bar_rect.position, Vector2(bar_rect.size.x * hp_ratio, bar_rect.size.y)), Color.RED.lerp(Color.GREEN, hp_ratio), true)
		_draw_health_grid(bar_rect.position, bar_rect.size.x, bar_rect.size.y)
		draw_rect(bar_rect, Color.BLACK, false, 1.0)
	if lab_pending:
		_draw_laboratory_preview()
	if select_mode and has_rally_point and can_set_rally_point():
		_draw_rally_line()
	if _is_test_mode_enabled():
		_draw_test_mode_contact_ranges()

func _draw_test_mode_contact_ranges():
	var contact_rect: Rect2 = _get_local_contact_rect()
	draw_rect(contact_rect, Color(1.0, 0.85, 0.05, 0.12), true)
	draw_rect(contact_rect, Color(1.0, 0.85, 0.05, 0.9), false, 3.0)
	if accepts_resource_dropoff and not is_under_construction:
		var dropoff_rect: Rect2 = _get_local_dropoff_rect().grow(36.0)
		draw_rect(dropoff_rect, Color(0.1, 1.0, 0.35, 0.08), true)
		draw_rect(dropoff_rect, Color(0.1, 1.0, 0.35, 0.85), false, 2.0)
	if is_under_construction:
		var construction_rect: Rect2 = contact_rect.grow(TEST_CONSTRUCTION_RANGE_PADDING)
		draw_rect(construction_rect, Color(0.1, 0.55, 1.0, 0.07), true)
		draw_rect(construction_rect, Color(0.1, 0.55, 1.0, 0.85), false, 2.0)
	draw_line(Vector2(-18.0, 0.0), Vector2(18.0, 0.0), Color(1.0, 0.2, 0.2, 0.95), 3.0)
	draw_line(Vector2(0.0, -18.0), Vector2(0.0, 18.0), Color(1.0, 0.2, 0.2, 0.95), 3.0)

func _draw_laboratory_preview():
	var cells := _get_laboratory_cells()
	if cells.is_empty():
		return
	var center := to_local(_get_cells_bottom_center(cells))
	var size := LAB_TEXTURE.get_size() * LAB_VISUAL_SCALE
	var rect := Rect2(center + Vector2(-size.x * 0.5, -size.y), size)
	var can_build := _can_place_laboratory()
	var fill := Color(0.0, 0.8, 0.22, 0.28) if can_build else Color(1.0, 0.08, 0.05, 0.35)
	var line := Color(0.0, 1.0, 0.3, 0.9) if can_build else Color(1.0, 0.16, 0.1, 0.95)
	draw_rect(rect, fill, true)
	draw_rect(rect, line, false, 2.0)
	draw_texture_rect(LAB_TEXTURE, rect, false, Color(0.45, 0.45, 0.45, 0.55))

func _draw_construction_bands():
	var visual_rect = _get_visual_rect()
	var band_height = visual_rect.size.y / float(CONSTRUCTION_BANDS)
	var built_bands = clampi(floori(construction_progress * CONSTRUCTION_BANDS + 0.0001), 0, CONSTRUCTION_BANDS)
	for i in range(CONSTRUCTION_BANDS):
		var band_from_bottom = CONSTRUCTION_BANDS - 1 - i
		var band_rect = Rect2(
			Vector2(visual_rect.position.x, visual_rect.position.y + (i * band_height)),
			Vector2(visual_rect.size.x, band_height)
		)
		if band_from_bottom >= built_bands:
			draw_rect(band_rect, Color(0.03, 0.03, 0.03, 0.72), true)
			draw_rect(band_rect, Color(0.7, 0.78, 0.82, 0.45), false, 1.0)
		else:
			draw_rect(band_rect, Color(0.2, 0.75, 0.35, 0.12), true)
			draw_rect(band_rect, Color(0.2, 0.95, 0.45, 0.35), false, 1.0)

func _draw_health_grid(bar_pos: Vector2, bar_width: float, bar_height: float):
	var grid_count = min(floor(max_hp / 100.0), 50)
	if grid_count > 1:
		var segment_width = bar_width / grid_count
		for i in range(1, int(grid_count)):
			var line_x = bar_pos.x + (i * segment_width)
			draw_line(Vector2(line_x, bar_pos.y), Vector2(line_x, bar_pos.y + bar_height), Color(0, 0, 0, 0.4), 1.0)

func _draw_rally_line():
	var target_pos = rally_resource.global_position if is_instance_valid(rally_resource) else rally_position
	var start = Vector2.ZERO
	var end = to_local(target_pos)
	var line_color = Color(0.1, 0.85, 1.0, 0.9)
	var dash_length = 12.0
	var gap_length = 7.0
	var total_length = start.distance_to(end)
	if total_length < 8.0:
		return
	var dir = start.direction_to(end)
	var travelled = 0.0
	while travelled < total_length:
		var dash_start = start + dir * travelled
		var dash_end = start + dir * min(travelled + dash_length, total_length)
		draw_line(dash_start, dash_end, line_color, 2.0)
		travelled += dash_length + gap_length
	var arrow_size = 10.0
	var left = end - dir * arrow_size + dir.rotated(PI * 0.75) * arrow_size * 0.55
	var right = end - dir * arrow_size + dir.rotated(-PI * 0.75) * arrow_size * 0.55
	draw_line(end, left, line_color, 2.0)
	draw_line(end, right, line_color, 2.0)
