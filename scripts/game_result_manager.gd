extends Node

const START_MENU_SCENE := "res://scenes/ui/start_menu.tscn"
const ENEMY_UNIT_SCENE: PackedScene = preload("res://scenes/units/test_enemy.tscn")
const MUSEUM_NAME := "행소박물관"
const ENEMY_SPAWN_POINTS: Array[Vector2] = [
	Vector2(2000, 2000),
	Vector2(2000, -500),
]

const BASE_WAVE_COUNT := 3
const BASE_ENEMY_HP := 50
const BASE_ENEMY_DAMAGE := 6
const BASE_ENEMY_SPEED := 250.0
const BASE_ENEMY_COOLDOWN := 1.0
const BASE_ENEMY_ATTACK_RANGE := 90.0
const BASE_ENEMY_DETECTION_RANGE := 400.0
const WAVE_SCALE := 1.5
const WAVES_PER_STAT_SCALE := 3
const ENEMY_ORDERS_PER_TICK := 3
const ENEMY_GUARD_ORDER_DISTANCE_SQ := 4096.0
const MAX_ENEMY_SPAWNS_PER_FRAME := 1
const HALF_HP_COUNTER_SPAWN_COUNT := 50
const POST_HALF_HP_WAVE_STEP := 10
const POST_HALF_HP_MAX_WAVE_COUNT := 50
const LOW_HP_BATCH_SPAWN_COUNT := 10
const LOW_HP_BATCH_INTERVAL := 0.5
const LOW_HP_BATCHES_PER_SEQUENCE := 10

@export var victory_target_path: NodePath
@export var result_delay: float = 3.0
@export var enemy_order_interval: float = 1.2
@export var enemy_wave_interval: float = 120.0

var result_pending := false
var result_shown := false
var result_title := ""
var result_message := ""
var result_timer := 0.0
var result_layer: CanvasLayer = null
var objective_layer: CanvasLayer = null
var objective_panel: PanelContainer = null
var objective_label: Label = null
var objective_close_button: Button = null
var objective_collapsed: bool = false
var enemy_order_timer: float = 0.0
var enemy_wave_timer: float = 120.0
var enemy_wave_index: int = 0
var enemy_order_cursor: int = 0
var half_hp_counter_spawned: bool = false
var post_half_hp_wave_count: int = 0
var low_hp_resistance_announced: bool = false
var low_hp_sequence_active: bool = false
var low_hp_batch_timer: float = 0.0
var low_hp_batches_remaining: int = 0
var spawned_enemies: Array[Node2D] = []
var pending_enemy_spawn_jobs: Array[Dictionary] = []

func _ready():
	enemy_wave_timer = enemy_wave_interval
	_create_objective_ui()
	_update_objective_ui()

func _process(delta: float):
	if not result_pending and not result_shown:
		_process_cursed_lapis_counterattacks(delta)
		_process_low_hp_resistance_sequence(delta)
		_process_enemy_waves(delta)
		_process_enemy_spawn_queue()
		_process_enemy_orders(delta)
		_update_objective_ui()

	if result_shown:
		return
	if result_pending:
		result_timer -= delta
		if result_timer <= 0.0:
			_show_result()
		return
	if _is_victory_condition_met():
		_queue_result("승리", "적의 건물을 파괴했습니다")
	elif _is_defeat_condition_met():
		_queue_result("패배", "박물관이 파괴되었습니다")

func _create_objective_ui():
	objective_layer = CanvasLayer.new()
	objective_layer.name = "ObjectiveLayer"
	objective_layer.layer = 40
	add_child(objective_layer)

	var wrapper := Control.new()
	wrapper.name = "ObjectiveBox"
	wrapper.position = Vector2(12, 12)
	objective_layer.add_child(wrapper)

	objective_panel = PanelContainer.new()
	objective_panel.custom_minimum_size = Vector2(430, 92)
	wrapper.add_child(objective_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 8)
	objective_panel.add_child(margin)

	objective_label = Label.new()
	objective_label.add_theme_font_size_override("font_size", 16)
	margin.add_child(objective_label)

	objective_close_button = Button.new()
	objective_close_button.text = "X"
	objective_close_button.custom_minimum_size = Vector2(24, 24)
	objective_close_button.size = Vector2(24, 24)
	objective_close_button.position = Vector2(402, 64)
	objective_close_button.add_theme_color_override("font_color", Color(1.0, 0.1, 0.1, 1.0))
	objective_close_button.add_theme_color_override("font_hover_color", Color(1.0, 0.35, 0.35, 1.0))
	objective_close_button.pressed.connect(_collapse_objective_ui)
	wrapper.add_child(objective_close_button)

func _update_objective_ui():
	if not is_instance_valid(objective_label):
		return
	if objective_collapsed:
		objective_label.text = "소환까지: %s    다음 적: %d" % [
			_format_time(enemy_wave_timer),
			_get_next_wave_count(),
		]
	else:
		objective_label.text = "승리조건: 저주받은 청금석 파괴\n패배조건: 행소박물관 전멸\n소환까지: %s    다음 적: %d" % [
			_format_time(enemy_wave_timer),
			_get_next_wave_count(),
		]

func _collapse_objective_ui():
	objective_collapsed = true
	if is_instance_valid(objective_panel):
		objective_panel.custom_minimum_size = Vector2(270, 42)
	if is_instance_valid(objective_close_button):
		objective_close_button.hide()
	_update_objective_ui()

func _process_enemy_waves(delta: float):
	enemy_wave_timer = max(0.0, enemy_wave_timer - delta)
	if enemy_wave_timer > 0.0:
		return
	if low_hp_resistance_announced:
		if low_hp_sequence_active or _has_active_or_pending_enemies():
			return
		_start_low_hp_resistance_sequence()
		enemy_wave_timer = enemy_wave_interval
		return
	_spawn_enemy_wave()
	enemy_wave_timer = enemy_wave_interval

func _spawn_enemy_wave():
	var enemy_count := _get_next_wave_count()
	if half_hp_counter_spawned:
		post_half_hp_wave_count = enemy_count
	if enemy_wave_index > 0 and enemy_wave_index % WAVES_PER_STAT_SCALE == 0:
		_show_hud_notice("적이 강해졌습니다")
	_spawn_enemies(enemy_count)
	enemy_wave_index += 1

func _spawn_enemies(enemy_count: int):
	if enemy_count <= 0:
		return
	var stat_scale := _get_current_enemy_stat_scale()
	pending_enemy_spawn_jobs.append({
		"count": enemy_count,
		"stat_scale": stat_scale
	})

func _process_enemy_spawn_queue():
	if pending_enemy_spawn_jobs.is_empty():
		return
	var parent := _get_enemy_parent()
	if not is_instance_valid(parent):
		return
	var remaining_budget := MAX_ENEMY_SPAWNS_PER_FRAME
	while remaining_budget > 0 and not pending_enemy_spawn_jobs.is_empty():
		var job: Dictionary = pending_enemy_spawn_jobs[0]
		var count: int = int(job.get("count", 0))
		if count <= 0:
			pending_enemy_spawn_jobs.pop_front()
			continue
		_spawn_enemy_instance(parent, float(job.get("stat_scale", 1.0)), spawned_enemies.size())
		count -= 1
		remaining_budget -= 1
		if count <= 0:
			pending_enemy_spawn_jobs.pop_front()
		else:
			job["count"] = count
			pending_enemy_spawn_jobs[0] = job

func _spawn_enemy_instance(parent: Node, stat_scale: float, spawn_index: int):
	var enemy := ENEMY_UNIT_SCENE.instantiate()
	parent.add_child(enemy)
	if enemy is Node2D:
		var spawn_point := ENEMY_SPAWN_POINTS[spawn_index % ENEMY_SPAWN_POINTS.size()]
		var jitter := Vector2(randf_range(-36.0, 36.0), randf_range(-36.0, 36.0))
		enemy.global_position = spawn_point + jitter
		_configure_enemy_unit(enemy, stat_scale)
		spawned_enemies.append(enemy)
		_send_enemy_toward_battle(enemy)

func _get_current_enemy_stat_scale() -> float:
	var stat_tier: int = floori(float(enemy_wave_index) / float(WAVES_PER_STAT_SCALE))
	return pow(WAVE_SCALE, float(stat_tier))

func _process_cursed_lapis_counterattacks(_delta: float):
	var target := get_node_or_null(victory_target_path)
	if not is_instance_valid(target) or not ("hp" in target) or not ("max_hp" in target) or target.max_hp <= 0:
		return
	var hp_ratio: float = clamp(float(target.hp) / float(target.max_hp), 0.0, 1.0)
	if not half_hp_counter_spawned and hp_ratio <= 0.5:
		half_hp_counter_spawned = true
		_show_hud_notice("저주받은 청금석이 저항한다")
		_spawn_enemies(HALF_HP_COUNTER_SPAWN_COUNT)
	if hp_ratio <= 0.1:
		if not low_hp_resistance_announced:
			low_hp_resistance_announced = true
			_show_hud_notice("저주받은 청금석이 최후의 저항을 합니다.")
			_start_low_hp_resistance_sequence()
			enemy_wave_timer = enemy_wave_interval

func _start_low_hp_resistance_sequence():
	if low_hp_sequence_active:
		return
	low_hp_sequence_active = true
	low_hp_batches_remaining = LOW_HP_BATCHES_PER_SEQUENCE
	low_hp_batch_timer = 0.0

func _process_low_hp_resistance_sequence(delta: float):
	if not low_hp_sequence_active:
		return
	low_hp_batch_timer = max(0.0, low_hp_batch_timer - delta)
	if low_hp_batch_timer > 0.0:
		return
	_spawn_enemies(LOW_HP_BATCH_SPAWN_COUNT)
	low_hp_batches_remaining -= 1
	if low_hp_batches_remaining <= 0:
		low_hp_sequence_active = false
		enemy_wave_timer = enemy_wave_interval
		return
	low_hp_batch_timer = LOW_HP_BATCH_INTERVAL

func _get_enemy_parent() -> Node:
	if get_tree().current_scene:
		var units: Node = get_tree().current_scene.find_child("Units", true, false)
		if is_instance_valid(units):
			return units
	return self

func _configure_enemy_unit(enemy: Node, stat_scale: float):
	var hp_value: int = maxi(1, int(round(float(BASE_ENEMY_HP) * stat_scale)))
	var damage_value: int = maxi(1, int(round(float(BASE_ENEMY_DAMAGE) * stat_scale)))
	if "max_hp" in enemy:
		enemy.max_hp = hp_value
	if "hp" in enemy:
		enemy.hp = hp_value
	if "attack_damage" in enemy:
		enemy.attack_damage = damage_value
	if "attack_cooldown" in enemy:
		enemy.attack_cooldown = BASE_ENEMY_COOLDOWN
	if "attack_range" in enemy:
		enemy.attack_range = BASE_ENEMY_ATTACK_RANGE
	if "detection_range" in enemy:
		enemy.detection_range = BASE_ENEMY_DETECTION_RANGE
	if "speed" in enemy:
		enemy.speed = BASE_ENEMY_SPEED

func _send_enemy_toward_battle(enemy: Node2D):
	var guard_target := get_node_or_null(victory_target_path)
	if is_instance_valid(guard_target) and guard_target is Node2D and enemy.has_method("set_attack_move"):
		enemy.set_attack_move(guard_target.global_position + Vector2(randf_range(-160.0, 160.0), randf_range(-160.0, 160.0)))

func _process_enemy_orders(delta: float):
	enemy_order_timer -= delta
	if enemy_order_timer > 0.0:
		return
	enemy_order_timer = enemy_order_interval
	spawned_enemies = spawned_enemies.filter(func(enemy): return is_instance_valid(enemy))
	if spawned_enemies.is_empty():
		return

	var target: Node2D = _find_enemy_attack_target()
	var guard_target := get_node_or_null(victory_target_path)
	var orders_this_tick: int = mini(ENEMY_ORDERS_PER_TICK, spawned_enemies.size())
	for i in range(orders_this_tick):
		if enemy_order_cursor >= spawned_enemies.size():
			enemy_order_cursor = 0
		var enemy: Node2D = spawned_enemies[enemy_order_cursor]
		enemy_order_cursor += 1
		if target:
			_order_enemy_attack_if_needed(enemy, target)
		elif is_instance_valid(guard_target) and guard_target is Node2D:
			_order_enemy_guard_if_needed(enemy, guard_target)

func _order_enemy_attack_if_needed(enemy: Node2D, target: Node2D):
	if not is_instance_valid(enemy) or not is_instance_valid(target) or not enemy.has_method("force_attack_target"):
		return
	var target_id: int = target.get_instance_id()
	if int(enemy.get_meta("manager_attack_target_id", 0)) == target_id:
		return
	enemy.set_meta("manager_attack_target_id", target_id)
	enemy.set_meta("manager_guard_position", Vector2.INF)
	enemy.force_attack_target(target)

func _order_enemy_guard_if_needed(enemy: Node2D, guard_target: Node2D):
	if not is_instance_valid(enemy) or not is_instance_valid(guard_target) or not enemy.has_method("set_attack_move"):
		return
	var guard_pos: Vector2 = enemy.get_meta("manager_guard_position", Vector2.INF)
	if guard_pos == Vector2.INF:
		guard_pos = guard_target.global_position + Vector2(randf_range(-160.0, 160.0), randf_range(-160.0, 160.0))
		enemy.set_meta("manager_guard_position", guard_pos)
	if enemy.global_position.distance_squared_to(guard_pos) <= ENEMY_GUARD_ORDER_DISTANCE_SQ:
		return
	enemy.set_meta("manager_attack_target_id", 0)
	enemy.set_attack_move(guard_pos)

func _find_enemy_attack_target() -> Node2D:
	var guard_target := get_node_or_null(victory_target_path)
	var origin: Vector2 = guard_target.global_position if is_instance_valid(guard_target) and guard_target is Node2D else Vector2.ZERO
	var best: Node2D = null
	var best_dist: float = INF
	for target in _get_cached_enemy_attack_targets():
		if not _is_valid_enemy_target(target):
			continue
		var dist: float = origin.distance_squared_to(target.global_position)
		if dist < best_dist:
			best_dist = dist
			best = target
	return best

func _get_cached_enemy_attack_targets() -> Array:
	var manager := get_tree().get_first_node_in_group("UnitManager")
	if manager and manager.has_method("get_cached_ally_targets"):
		return manager.get_cached_ally_targets()
	return get_tree().get_nodes_in_group("Unit") + get_tree().get_nodes_in_group("Building")

func _is_valid_enemy_target(target) -> bool:
	return is_instance_valid(target) and target is Node2D and target.is_in_group("Ally") and "hp" in target and target.hp > 0

func _has_active_or_pending_enemies() -> bool:
	spawned_enemies = spawned_enemies.filter(func(enemy): return is_instance_valid(enemy))
	if not spawned_enemies.is_empty():
		return true
	return not pending_enemy_spawn_jobs.is_empty()

func _get_next_wave_count() -> int:
	if low_hp_resistance_announced:
		return LOW_HP_BATCH_SPAWN_COUNT * LOW_HP_BATCHES_PER_SEQUENCE
	if half_hp_counter_spawned:
		return mini(post_half_hp_wave_count + POST_HALF_HP_WAVE_STEP, POST_HALF_HP_MAX_WAVE_COUNT)
	return BASE_WAVE_COUNT + enemy_wave_index

func _show_hud_notice(text: String):
	var hud := get_tree().current_scene.find_child("HUD", true, false) if get_tree().current_scene else null
	if hud and hud.has_method("show_notice"):
		hud.show_notice(text)

func _format_time(seconds: float) -> String:
	var total_seconds: int = maxi(0, int(ceil(seconds)))
	var minutes: int = floori(float(total_seconds) / 60.0)
	var secs: int = total_seconds % 60
	return "%02d:%02d" % [minutes, secs]

func _queue_result(title: String, message: String):
	result_pending = true
	result_title = title
	result_message = message
	result_timer = result_delay

func _is_victory_condition_met() -> bool:
	var target := get_node_or_null(victory_target_path)
	if not is_instance_valid(target):
		return true
	if "hp" in target and target.hp <= 0:
		return true
	return false

func _is_defeat_condition_met() -> bool:
	for building in get_tree().get_nodes_in_group("Building"):
		if not is_instance_valid(building):
			continue
		if "building_name" in building and str(building.building_name).strip_edges() == MUSEUM_NAME:
			if not ("hp" in building) or building.hp > 0:
				return false
	return true

func _show_result():
	result_shown = true
	get_tree().paused = true
	_create_result_ui()

func _create_result_ui():
	result_layer = CanvasLayer.new()
	result_layer.name = "GameResultLayer"
	result_layer.layer = 100
	result_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(result_layer)

	var overlay := ColorRect.new()
	overlay.name = "ResultOverlay"
	overlay.color = Color(0, 0, 0, 0.72)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	result_layer.add_child(overlay)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.process_mode = Node.PROCESS_MODE_ALWAYS
	overlay.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(420, 230)
	panel.process_mode = Node.PROCESS_MODE_ALWAYS
	center.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_bottom", 24)
	panel.add_child(margin)

	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 18)
	margin.add_child(box)

	var title_label := Label.new()
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.text = result_title
	title_label.add_theme_font_size_override("font_size", 42)
	box.add_child(title_label)

	var message_label := Label.new()
	message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message_label.text = result_message
	message_label.add_theme_font_size_override("font_size", 22)
	box.add_child(message_label)

	var menu_button := Button.new()
	menu_button.text = "메뉴로 돌아가기"
	menu_button.custom_minimum_size = Vector2(190, 44)
	menu_button.process_mode = Node.PROCESS_MODE_ALWAYS
	menu_button.pressed.connect(_on_menu_button_pressed)
	box.add_child(menu_button)

func _on_menu_button_pressed():
	get_tree().paused = false
	get_tree().change_scene_to_file(START_MENU_SCENE)
