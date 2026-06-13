extends CharacterBody2D

var command_menus: Dictionary = {} 
var current_menu_page: String = "base"

# 1. 상태 및 설정 변수
enum State { IDLE, MOVING, ATTACK_MOVE, ATTACKING, MOVING_TO_RESOURCE, GATHERING, RETURNING_RESOURCE, MOVING_TO_BUILD, BUILDING }
const BUILD_CONTACT_HEIGHT_RATIO := 0.5
const BUILD_APPROACH_RANGE_PADDING := 44.0
const BUILD_PROGRESS_RANGE_PADDING := 56.0
var current_state = State.IDLE
var last_direction : String = "front"
var hover_mode : bool = false 

# 인스펙터에서 조정 가능한 능력치
@export_group("Unit Stats")
@export var speed : float = 250.0
@export var max_hp : int = 45 
@export var hp : int = 45:
	set(value):
		hp = clamp(value, 0, max_hp)
		if hp <= 0:
			_die()
		queue_redraw()

@export var attack_damage : int = 6
@export var attack_cooldown : float = 1.0
@export var attack_range : float = 180.0    
@export var detection_range : float = 400.0  
@export var can_attack: bool = true

@export_group("Mana")
@export var max_mana: int = 0
@export var mana: int = 0:
	set(value):
		mana = clamp(value, 0, max_mana)
		queue_redraw()
@export var mana_regen_per_second: float = 0.0
@export var can_auto_heal: bool = false
@export var heal_range: float = 300.0
@export var heal_cooldown: float = 0.2
@export var heal_per_mana: int = 3
var heal_timer: float = 0.0
var mana_regen_progress: float = 0.0
var heal_animation_timer: float = 0.0

@export_group("Gathering")
@export var can_gather: bool = false
@export var can_build: bool = false
@export var gather_amount: int = 5
@export var gather_time: float = 5.0
@export var gather_range: float = 72.0
@export var dropoff_range: float = 72.0
@export var auto_find_resource_range: float = 450.0
@export var separation_radius: float = 16.0
@export var separation_strength: float = 55.0
@export var obstacle_spacing: float = 18.0
@export var obstacle_spacing_strength: float = 120.0
@export var gather_nav_update_interval: float = 0.25
@export var gather_stuck_check_interval: float = 0.2

var gather_target: Node2D = null
var dropoff_target: Node2D = null
var carried_resource: int = 0
var carried_resource_kind: String = "mineral"
var gather_timer: float = 0.0
var gather_nav_update_timer: float = 0.0
var gather_stuck_check_timer: float = 0.0
var gather_anim_timer: float = 0.0
var hidden_for_excavation: bool = false
var mineral_gather_voice_active: bool = false
var professor_heal_voice_active: bool = false
var build_target_position: Vector2 = Vector2.ZERO
var build_scene: PackedScene = null
var build_placement: Node = null
var build_site: Node2D = null
var build_cells: Array = []
var build_config: Dictionary = {}
var build_cost_pending_refund: bool = false
var build_orbit_angle: float = 0.0
var build_orbit_radius: float = 44.0
var command_queue: Array = []
var executing_queued_command: bool = false
var is_dying: bool = false
var base_speed: float = 0.0
var base_max_hp: int = 0
var base_attack_damage: int = 0
var base_attack_cooldown: float = 0.0
var base_gather_amount: int = 0
var base_max_mana: int = 0
var base_heal_per_mana: int = 0

# 전투 상태
var attack_timer : float = 0.0
var attack_target: Node2D = null
var attack_move_destination : Vector2 = Vector2.ZERO 
var direct_attack_order: bool = false
var attack_damage_pending: bool = false
var attack_nav_update_timer: float = 0.0
var last_attack_nav_target_position: Vector2 = Vector2.ZERO
var has_attack_nav_target_position: bool = false
var attack_scan_timer: float = 0.0
const ATTACK_NAV_UPDATE_INTERVAL := 0.25

@export_group("Unit Identity")
@export var unit_name: String
@export var population_cost: int = 1
@export var icon_texture: Texture2D = preload("res://icon/stduent_icon.png")
var kills: int = 0
var upgrade_level_name: String = "+1 공격력"

var select_mode : bool = false
var last_pos: Vector2 = Vector2.ZERO
var stuck_timer: float = 0.0
var recovery_timer: float = 0.0
var recovery_dir: Vector2 = Vector2.ZERO
enum RecoveryPhase { SIDE_LEFT, SIDE_RIGHT, BACK }
var current_recovery_phase = RecoveryPhase.SIDE_LEFT
var recovery_attempt_count : int = 0
var reroute_attempt_count: int = 0
var separation_update_timer: float = 0.0
var obstacle_update_timer: float = 0.0
var cached_separation_push: Vector2 = Vector2.ZERO
var cached_obstacle_push: Vector2 = Vector2.ZERO
const SEPARATION_UPDATE_INTERVAL := 0.2
const OBSTACLE_UPDATE_INTERVAL := 0.32
const MAX_SEPARATION_CHECKS := 18
const MAX_OBSTACLE_CHECKS := 10

const DEPTH_SORT_OFFSET := 2048
const LAPIS_CARRY_TEXTURE: Texture2D = preload("res://icon/lapis.png")
const RELICS_CARRY_TEXTURE: Texture2D = preload("res://icon/relics.png")

# 2. 노드 참조
@onready var nav_agent: NavigationAgent2D = $NavigationAgent2D
@onready var sprite = $AnimatedSprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D
var carried_resource_sprite: Sprite2D = null
var unit_manager: Node = null
var last_heal_effect_msec: int = 0
var last_bullet_hit_effect_msec: int = 0

func set_hover(is_hover: bool):
	if hover_mode != is_hover:
		hover_mode = is_hover
		queue_redraw() 

func _ready():
	unit_manager = get_tree().get_first_node_in_group("UnitManager")
	_store_base_stats()
	apply_global_upgrades()
	var pure_kr_name = unit_name.strip_edges() 
	_setup_menu_data(pure_kr_name)
	
	input_pickable = true
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	
	add_to_group("Unit")
	nav_agent.path_desired_distance = 10.0
	nav_agent.target_desired_distance = 10.0
	nav_agent.path_desired_distance = 18.0
	nav_agent.target_desired_distance = 18.0
	nav_agent.path_max_distance = 90.0
	if is_in_group("Enemy"):
		nav_agent.path_desired_distance = 32.0
		nav_agent.target_desired_distance = 32.0
		nav_agent.path_max_distance = 160.0
	_play_unit_animation("stand_" + last_direction)
	sprite.z_index = 1
	_create_carried_resource_sprite()
	_update_depth_sort()

func _store_base_stats():
	if base_max_hp > 0:
		return
	base_speed = speed
	base_max_hp = max_hp
	base_attack_damage = attack_damage
	base_attack_cooldown = attack_cooldown
	base_gather_amount = gather_amount
	base_max_mana = max_mana
	base_heal_per_mana = heal_per_mana

func apply_global_upgrades():
	if is_in_group("Enemy"):
		return
	_store_base_stats()
	var manager = get_tree().get_first_node_in_group("UnitManager")
	if not manager:
		return
	var hp_ratio := float(hp) / float(max(max_hp, 1))
	max_hp = max(1, int(round(float(base_max_hp) * manager.get_body_multiplier())))
	hp = clampi(int(round(float(max_hp) * hp_ratio)), 1, max_hp)
	attack_damage = max(0, int(round(float(base_attack_damage) * manager.get_power_multiplier())))
	speed = base_speed
	attack_cooldown = base_attack_cooldown
	gather_amount = base_gather_amount
	max_mana = base_max_mana
	heal_per_mana = base_heal_per_mana
	var trait_id: String = manager.get_unit_trait_upgrade_id(self) if manager.has_method("get_unit_trait_upgrade_id") else ""
	if trait_id == "student" and manager.get_upgrade_level("student") > 0:
		gather_amount = base_gather_amount * 2
	elif trait_id == "m_student" and manager.get_upgrade_level("m_student") > 0:
		attack_cooldown = base_attack_cooldown * 0.5
	elif trait_id == "professor" and manager.get_upgrade_level("professor") > 0:
		max_mana = max(1, int(round(float(base_max_mana) * 1.5)))
		mana = min(max_mana, max(mana, base_max_mana))
		heal_per_mana = base_heal_per_mana + 2
	elif trait_id == "armi" and manager.get_upgrade_level("armi") > 0:
		speed = base_speed * 1.5
	queue_redraw()
	
func get_current_buttons() -> Array:
	return command_menus.get(current_menu_page, [])

func _on_mouse_entered():
	hover_mode = true
	queue_redraw()

func _on_mouse_exited():
	hover_mode = false
	queue_redraw()
	
func _get_pure_name() -> String:
	var regex = RegEx.new()
	regex.compile("[^가-힣]") 
	return regex.sub(name, "", true)
	
func _setup_menu_data(type_name: String):
	var base_movement = [
		{"index": 0, "icon_path": "res://assets/btu/move_btu.png", "function": "_on_move_pressed", "tooltip": "[color=#ffd84a]이동[/color]\n유닛을 [color=#56a8ff]이동[/color]시킨다\n[color=#ff9f33][lb]우클릭[rb][/color]"},
		{"index": 1, "key": KEY_S, "icon_path": "res://assets/btu/stop_btu.png", "function": "_on_stop_pressed", "tooltip": "[color=#ffd84a]정지[/color]\n유닛의 행동을 [color=#56a8ff]정지[/color]시킨다\n[color=#ff9f33][lb]S[rb][/color]"},
		{"index": 2, "key": KEY_A, "icon_path": "res://assets/btu/attack_btu.png", "function": "_on_attack_pressed", "tooltip": "[color=#ffd84a]공격[/color]\n유닛에게 [color=#56a8ff]공격[/color]명령을 내린다\n[color=#ff9f33][lb]A + 우클릭[rb][/color]"}
	]
	command_menus = { "base": base_movement.duplicate() }
	
	match type_name:
		"학생", "테스트유닛":
			var student_base = base_movement.duplicate()
			if can_gather:
				student_base.append({"index": 4, "icon_path": "res://assets/btu/gathering_btu.png", "function": "_on_gathering_pressed", "tooltip": "[color=#ffd84a]자원으로 이동[/color]\n[color=#56a8ff]'학생'[/color] 유닛은 [color=#ff9f33]자원채취[/color] 가능\n[color=#ff9f33]청금석[/color]과 [color=#ff9f33]유물[/color] 채취 가능"})
			if can_build:
				student_base.append({"index": 6, "key": KEY_B, "icon_path": "res://assets/btu/build_btu.png", "function": "change_menu_page", "argument": "build_basic", "tooltip": "[color=#ff9f33]건설[/color]\n[color=#56a8ff]'학생'[/color] 유닛은 [color=#ff9f33]건물건설[/color] 가능\n건물선택 후 건설\n[color=#ff9f33][lb]B[rb][/color]"})
			
			var student_build = [
				{"index": 0, "key": KEY_C, "icon_path": "res://assets/btu/museum_but.png", "function": "_on_build_basic_pressed", "tooltip": "행소박물관\n건설시간 40초\n필요 자원: 청금석 400 / 유물 0\n인구수 제한 +10"},
				{"index": 1, "key": KEY_F, "icon_path": "res://assets/btu/resttaurant_btu.png", "function": "_on_build_supply_pressed", "tooltip": "공대식당\n건설시간 20초\n필요 자원: 청금석 50 / 유물 0\n인구수 제한 +8"},
				{"index": 2, "key": KEY_D, "icon_path": "res://assets/btu/dok_btu.png", "function": "_on_build_barracks_pressed", "tooltip": "덕래관\n건설시간 25초\n필요 자원: 청금석 150 / 유물 0\n필요 조건: 공대식당\n공격유닛 생산"},
				{"index": 3, "key": KEY_E, "icon_path": "res://assets/btu/excavation_site_btu-sheet.png", "function": "_on_build_excavation_pressed", "tooltip": "발굴지\n건설시간 25초\n필요 자원: 청금석 75 / 유물 0\n유적지 위에만 건설 가능\n유물을 채취할 수 있음"},
				{"index": 4, "key": KEY_T, "icon_path": "res://assets/btu/armi_traing_btu.png", "function": "_on_build_army_training_pressed", "tooltip": "훈련소\n건설시간 30초\n필요 자원: 청금석 150 / 유물 50\n필요 조건: 덕래관"},
				{"index": 8, "key": KEY_ESCAPE, "icon_path": "res://assets/btu/cancel_btu.png", "function": "change_menu_page", "argument": "base"}
			]
			var student_searching = [
				{"index": 8, "key": KEY_ESCAPE, "icon_path": "res://assets/btu/cancel_btu.png", "function": "change_menu_page", "argument": "base"}
			]
			command_menus = {
				"base": student_base,
				"build_basic": student_build,
				"searching": student_searching
			}
		"건설로봇", "일꾼":
			var scv_base = base_movement.duplicate()
			scv_base.append({"index": 2, "key": KEY_A, "icon_path": "res://assets/ui/icon_attack.png", "function": "_on_attack_pressed"})
			scv_base.append({"index": 3, "key": KEY_B, "icon_path": "res://assets/ui/icon_build.png", "function": "change_menu_page", "argument": "build_basic"})
			
			var scv_build = [
				{"index": 0, "key": KEY_C, "icon_path": "res://assets/ui/icon_center.png", "function": "_on_build_cc_pressed"},
				{"index": 1, "key": KEY_S, "icon_path": "res://assets/ui/icon_supply.png", "function": "_on_build_supply_pressed"},
				{"index": 8, "key": KEY_ESCAPE, "icon_path": "res://assets/ui/icon_cancel.png", "function": "change_menu_page", "argument": "base"}
			]
			command_menus = {
				"base": scv_base,
				"build_basic": scv_build
			}
		"메딕":
			var medic_base = base_movement.duplicate()
			medic_base.append({"index": 2, "key": KEY_H, "icon_path": "res://assets/ui/icon_heal.png", "function": "_on_heal_pressed"})
			command_menus = { "base": medic_base }

	if command_menus.size() == 1 and command_menus.has("base"):
		var ally_base = base_movement.duplicate()
		if can_gather:
			ally_base.append({"index": 4, "icon_path": "res://assets/btu/gathering_btu.png", "function": "_on_gathering_pressed", "tooltip": "[color=#ffd84a]자원으로 이동[/color]\n[color=#56a8ff]'학생'[/color] 유닛은 [color=#ff9f33]자원채취[/color] 가능\n[color=#ff9f33]청금석[/color]과 [color=#ff9f33]유물[/color] 채취 가능"})
		command_menus = { "base": ally_base }

func _physics_process(delta):
	if is_dying:
		return
	_update_depth_sort()
	if attack_timer > 0.0:
		attack_timer -= delta
	if heal_timer > 0.0:
		heal_timer -= delta
	_process_mana_regen(delta)

	match current_state:
		State.MOVING:
			_process_navigation_moving(delta)
			_check_if_stuck(delta) 
		State.IDLE:
			var idle_enemy = _get_attack_move_enemy(delta)
			if idle_enemy:
				attack_target = idle_enemy
				current_state = State.ATTACKING
				direct_attack_order = true
				attack_move_destination = Vector2.ZERO
				attack_damage_pending = false
			else:
				velocity = velocity.move_toward(Vector2.ZERO, speed * 4.0 * delta)
				move_and_slide()
		State.ATTACK_MOVE:
			var enemy = _get_attack_move_enemy(delta)
			if enemy:
				attack_target = enemy
				current_state = State.ATTACKING
			else:
				var attack_move_finished := false
				if is_in_group("Enemy"):
					attack_move_finished = global_position.distance_squared_to(nav_agent.target_position) <= 1024.0
				else:
					attack_move_finished = nav_agent.is_navigation_finished()
				if attack_move_finished:
					# 목적지에 도착해도 공격 이동 모드는 유지한다.
					velocity = Vector2.ZERO
					_play_unit_animation("stand_" + last_direction)
				else:
					_process_navigation_moving(delta) 
					_check_if_stuck(delta)
		State.ATTACKING:
			_process_attack_logic(delta)
		State.MOVING_TO_RESOURCE:
			_process_moving_to_resource(delta)
		State.GATHERING:
			_process_gathering(delta)
		State.RETURNING_RESOURCE:
			_process_returning_resource(delta)
		State.MOVING_TO_BUILD:
			_process_moving_to_build(delta)
		State.BUILDING:
			_process_building(delta)

	_process_auto_heal(delta)
	_process_heal_animation(delta)
	_apply_soft_separation(delta)
	_apply_obstacle_spacing(delta)
	_update_depth_sort()

func _update_depth_sort():
	z_index = clampi(int(global_position.y) + DEPTH_SORT_OFFSET, 0, 4096)

func _get_unit_manager():
	if not is_instance_valid(unit_manager):
		unit_manager = get_tree().get_first_node_in_group("UnitManager")
	return unit_manager

func _get_cached_units() -> Array:
	var manager = _get_unit_manager()
	if manager and manager.has_method("get_cached_units"):
		return manager.get_cached_units()
	return get_tree().get_nodes_in_group("Unit")

func _get_cached_enemies() -> Array:
	var manager = _get_unit_manager()
	if manager and manager.has_method("get_cached_enemies"):
		return manager.get_cached_enemies()
	return get_tree().get_nodes_in_group("Enemy")

func _get_cached_obstacles() -> Array:
	var manager = _get_unit_manager()
	if manager and manager.has_method("get_cached_obstacles"):
		return manager.get_cached_obstacles()
	return get_tree().get_nodes_in_group("Building") + get_tree().get_nodes_in_group("ResourceDeposit") + get_tree().get_nodes_in_group("Ruins")
			
func _check_if_stuck(delta):
	if global_position.distance_to(last_pos) < 0.35 and velocity.length() > speed * 0.2:
		stuck_timer += delta
	else:
		stuck_timer = 0.0
		recovery_attempt_count = 0
		last_pos = global_position

	if stuck_timer > 0.45:
		_start_stuck_recovery()
		stuck_timer = 0.0
		
func _start_stuck_recovery():
	recovery_timer = 0.08
	recovery_attempt_count += 1
	
	var move_dir = velocity.normalized()
	if move_dir == Vector2.ZERO:
		move_dir = global_position.direction_to(nav_agent.target_position)

	match current_recovery_phase:
		RecoveryPhase.SIDE_LEFT:
			recovery_dir = move_dir.rotated(deg_to_rad(-28))
			current_recovery_phase = RecoveryPhase.SIDE_RIGHT
		RecoveryPhase.SIDE_RIGHT:
			recovery_dir = move_dir.rotated(deg_to_rad(28))
			current_recovery_phase = RecoveryPhase.BACK
		RecoveryPhase.BACK:
			recovery_dir = -move_dir.rotated(randf_range(-0.12, 0.12))
			current_recovery_phase = RecoveryPhase.SIDE_LEFT
	
	if get_slide_collision_count() > 0:
		var col = get_slide_collision(0)
		recovery_dir = (recovery_dir + col.get_normal()).normalized()
	
	velocity = recovery_dir * speed * 0.45
	move_and_slide()
	if recovery_attempt_count >= 3:
		_reroute_blocked_order()
		recovery_attempt_count = 0

func _reroute_blocked_order():
	reroute_attempt_count += 1
	match current_state:
		State.MOVING:
			nav_agent.target_position = _get_reroute_point_around(nav_agent.target_position, 36.0)
		State.ATTACK_MOVE:
			nav_agent.target_position = _get_reroute_point_around(nav_agent.target_position, 42.0)
		State.MOVING_TO_RESOURCE:
			if is_instance_valid(gather_target):
				nav_agent.target_position = _get_resource_approach_position(gather_target)
		State.RETURNING_RESOURCE:
			if is_instance_valid(dropoff_target):
				nav_agent.target_position = _get_alternate_dropoff_position(dropoff_target)
		State.MOVING_TO_BUILD:
			build_orbit_angle += PI * 0.45
			nav_agent.target_position = _get_build_orbit_position(build_target_position, build_orbit_angle)
		_:
			pass
	last_pos = global_position
	stuck_timer = 0.0

func _get_reroute_point_around(target_pos: Vector2, radius: float) -> Vector2:
	var angle := float(reroute_attempt_count % 8) * TAU / 8.0
	return target_pos + Vector2(cos(angle), sin(angle)) * radius

func set_target(pos: Vector2, append_order: bool = false):
	_stop_mineral_gather_voice()
	if current_state == State.BUILDING:
		if append_order:
			_enqueue_command({"type": "move", "pos": pos})
		else:
			_clear_command_queue()
		return
	if append_order:
		_enqueue_command({"type": "move", "pos": pos})
		return
	if not executing_queued_command:
		_clear_command_queue()
	_clear_gather_order()
	_clear_build_order()
	attack_damage_pending = false
	nav_agent.target_position = pos
	current_state = State.MOVING
	stuck_timer = 0.0
	last_pos = global_position

func _process_navigation_moving(delta):
	if recovery_timer > 0:
		recovery_timer -= delta
		velocity = recovery_dir * speed * 0.45
		move_and_slide()
		if recovery_timer <= 0:
			nav_agent.target_position = nav_agent.target_position
		return

	if is_in_group("Enemy"):
		_process_enemy_light_navigation()
		return

	if nav_agent.is_navigation_finished():
		_stop_unit()
		return

	var next_path_pos = nav_agent.get_next_path_position()
	var dir = global_position.direction_to(next_path_pos)
	velocity = dir * speed
	move_and_slide()
	_update_animation(dir)

func _process_enemy_light_navigation():
	var target_pos: Vector2 = nav_agent.target_position
	var to_target: Vector2 = target_pos - global_position
	var arrive_distance: float = max(nav_agent.target_desired_distance, 22.0)
	if to_target.length_squared() <= arrive_distance * arrive_distance:
		if current_state == State.MOVING:
			_stop_unit()
		else:
			velocity = Vector2.ZERO
			_play_unit_animation("stand_" + last_direction)
		return
	var dir: Vector2 = to_target.normalized()
	velocity = dir * speed
	move_and_slide()
	_update_animation(dir)

func _stop_unit():
	# 일반 이동 명령이 끝난 경우에만 대기 상태로 전환한다.
	if current_state == State.MOVING:
		current_state = State.IDLE
		_start_next_queued_command()
	
	velocity = Vector2.ZERO
	_play_unit_animation("stand_" + last_direction)
	
	var manager = get_tree().get_first_node_in_group("UnitManager")
	if manager and manager.has_method("_refresh_command_mode_by_selection"):
		manager._refresh_command_mode_by_selection()

func stop_order():
	_stop_mineral_gather_voice()
	if current_state == State.BUILDING and is_instance_valid(build_site):
		if build_site.has_method("pause_construction"):
			build_site.pause_construction(self)
	if not executing_queued_command:
		_clear_command_queue()
	_clear_gather_order()
	_clear_build_order()
	attack_target = null
	attack_damage_pending = false
	current_state = State.IDLE
	velocity = Vector2.ZERO
	nav_agent.target_position = global_position
	_play_unit_animation("stand_" + last_direction)

func set_attack_move(pos: Vector2, append_order: bool = false):
	_stop_mineral_gather_voice()
	if not can_attack:
		set_target(pos, append_order)
		return
	if current_state == State.BUILDING:
		if append_order:
			_enqueue_command({"type": "attack_move", "pos": pos})
		else:
			_clear_command_queue()
		return
	if append_order:
		_enqueue_command({"type": "attack_move", "pos": pos})
		return
	if not executing_queued_command:
		_clear_command_queue()
	_clear_gather_order()
	_clear_build_order()
	attack_damage_pending = false
	attack_move_destination = pos
	direct_attack_order = false
	nav_agent.target_position = pos
	current_state = State.ATTACK_MOVE
	attack_target = null
	attack_scan_timer = randf_range(0.0, 0.16)
	stuck_timer = 0.0
	last_pos = global_position

func _process_attack_logic(delta):
	# 공격 대상이 사라졌거나 더 이상 공격할 수 없으면 다음 행동을 정한다.
	if not _is_valid_attack_target(attack_target):
		_handle_lost_attack_target()
		return

	var dist = _get_attack_target_distance(attack_target)
	if dist <= attack_range:
		velocity = Vector2.ZERO
		var dir_to_enemy = global_position.direction_to(attack_target.global_position)
		if attack_damage_pending:
			_process_pending_attack_damage()
		elif attack_timer <= 0.0:
			attack_damage_pending = true
			_update_attack_animation(dir_to_enemy)
			sprite.frame = 0
			_play_armi_fire_voice()
		else:
			_face_stand_direction(dir_to_enemy)
	else:
		attack_damage_pending = false
		# 사거리 밖이면 사거리 안으로 들어갈 때까지 추격한다.
		_update_attack_navigation_target(delta)
		_process_navigation_moving(delta)

func _handle_lost_attack_target():
	attack_damage_pending = false
	attack_target = null
	direct_attack_order = false
	attack_move_destination = global_position
	nav_agent.target_position = global_position
	velocity = Vector2.ZERO

	var next_enemy = _find_closest_enemy()
	if next_enemy:
		attack_target = next_enemy
		current_state = State.ATTACKING
		has_attack_nav_target_position = false
		attack_nav_update_timer = 0.0
		return

	current_state = State.IDLE
	attack_scan_timer = 0.0
	_play_unit_animation("stand_" + last_direction)

# 우클릭 직접 공격 명령에 사용한다.
func force_attack_target(target: Node2D):
	_stop_mineral_gather_voice()
	if not is_instance_valid(target) or target == self: return
	if not can_attack:
		set_target(target.global_position)
		return
	if current_state == State.BUILDING:
		return
	if current_state == State.ATTACKING and attack_target == target:
		return
	
	_clear_gather_order()
	_clear_build_order()
	attack_target = target
	current_state = State.ATTACKING
	direct_attack_order = true
	attack_move_destination = Vector2.ZERO
	attack_damage_pending = false
	attack_nav_update_timer = 0.0
	has_attack_nav_target_position = false

func _update_attack_navigation_target(delta: float):
	if not is_instance_valid(attack_target):
		return
	attack_nav_update_timer -= delta
	var target_pos := _get_attack_target_approach_position(attack_target)
	if attack_nav_update_timer > 0.0 and has_attack_nav_target_position and last_attack_nav_target_position.distance_squared_to(target_pos) < 576.0:
		return
	nav_agent.target_position = target_pos
	last_attack_nav_target_position = target_pos
	has_attack_nav_target_position = true
	attack_nav_update_timer = ATTACK_NAV_UPDATE_INTERVAL + randf_range(0.0, 0.12)

func _get_attack_target_distance(target: Node2D) -> float:
	if not is_instance_valid(target):
		return INF
	if target.has_method("get_rect"):
		var rect: Rect2 = target.get_rect()
		return global_position.distance_to(_get_closest_point_on_rect(rect, global_position))
	return global_position.distance_to(target.global_position)

func _get_attack_target_approach_position(target: Node2D) -> Vector2:
	if not is_instance_valid(target):
		return global_position
	if target.has_method("get_rect"):
		var rect: Rect2 = target.get_rect()
		var closest := _get_closest_point_on_rect(rect, global_position)
		var away := rect.get_center().direction_to(global_position)
		if away == Vector2.ZERO:
			away = Vector2.DOWN
		return closest + away.normalized() * min(max(attack_range * 0.45, 24.0), 48.0)
	return target.global_position

func _get_closest_point_on_rect(rect: Rect2, point: Vector2) -> Vector2:
	return Vector2(
		clamp(point.x, rect.position.x, rect.position.x + rect.size.x),
		clamp(point.y, rect.position.y, rect.position.y + rect.size.y)
	)

func _apply_damage_to_target():
	if is_instance_valid(attack_target):
		var dealt_damage := false
		var was_alive := _is_kill_count_target_alive(attack_target)
		if attack_target.has_method("take_damage"):
			attack_target.take_damage(attack_damage, self)
			dealt_damage = true
		elif "hp" in attack_target:
			attack_target.hp -= attack_damage
			dealt_damage = true
		if dealt_damage:
			_add_kill_if_target_died(attack_target, was_alive)
			var manager = get_tree().get_first_node_in_group("UnitManager")
			if is_in_group("Enemy") and manager and manager.has_method("play_enemy_voice"):
				manager.play_enemy_voice("fire", self)
			if manager and manager.has_method("is_graduate_unit") and manager.is_graduate_unit(self) and manager.has_method("play_graduate_voice"):
				manager.play_graduate_voice("hit", self)
		if _is_armi_unit() and attack_target.has_method("play_bullet_hit_effect"):
			attack_target.play_bullet_hit_effect()

func take_damage(amount: int, source = null):
	if is_in_group("Ally") and (not is_instance_valid(source) or source.is_in_group("Enemy")):
		var manager = get_tree().get_first_node_in_group("UnitManager")
		if manager and manager.has_method("notify_ally_under_attack"):
			manager.notify_ally_under_attack(self, "unit")
	hp -= amount

func _is_kill_count_target_alive(target) -> bool:
	return is_instance_valid(target) and target.is_in_group("Unit") and "hp" in target and target.hp > 0

func _add_kill_if_target_died(target, was_alive: bool):
	if not was_alive or target == self:
		return
	if not is_instance_valid(target) or not target.is_in_group("Unit"):
		return
	if not ("hp" in target) or target.hp > 0:
		return
	kills += 1
	var manager = get_tree().get_first_node_in_group("UnitManager")
	if manager and manager.has_method("_refresh_command_ui"):
		manager._refresh_command_ui()

func _play_armi_fire_voice():
	var manager = get_tree().get_first_node_in_group("UnitManager")
	if manager and manager.has_method("is_armi_unit") and manager.is_armi_unit(self) and manager.has_method("play_armi_voice"):
		manager.play_armi_voice("fire", self)

func _is_armi_unit() -> bool:
	var scene_path := str(scene_file_path if "scene_file_path" in self else "")
	return scene_path.ends_with("armi.tscn") or unit_name.strip_edges() == "예비군"

func _process_pending_attack_damage():
	if not sprite or not sprite.sprite_frames:
		_apply_damage_to_target()
		_finish_attack_swing()
		return
	var animation_name := String(sprite.animation)
	var frame_count: int = sprite.sprite_frames.get_frame_count(animation_name)
	if frame_count <= 0 or sprite.frame < frame_count - 1:
		return
	_apply_damage_to_target()
	_finish_attack_swing()

func _finish_attack_swing():
	attack_damage_pending = false
	attack_timer = attack_cooldown
	if is_instance_valid(attack_target):
		_face_stand_direction(global_position.direction_to(attack_target.global_position))
	else:
		_play_unit_animation("stand_" + last_direction)

func _face_stand_direction(dir: Vector2):
	if dir.length() < 0.1:
		return
	_update_facing_direction(dir)
	_play_unit_animation("stand_" + last_direction)

func start_gathering(resource: Node2D, dropoff: Node2D = null, append_order: bool = false):
	if not can_gather or not is_instance_valid(resource):
		return
	if current_state == State.BUILDING:
		if append_order:
			_enqueue_command({"type": "gather", "resource": resource, "dropoff": dropoff})
		else:
			_clear_command_queue()
		return
	if append_order:
		_enqueue_command({"type": "gather", "resource": resource, "dropoff": dropoff})
		return
	_clear_command_queue()
	_clear_build_order()
	gather_target = resource
	dropoff_target = dropoff if is_instance_valid(dropoff) else _find_nearest_dropoff()
	carried_resource = 0
	carried_resource_kind = "mineral"
	gather_timer = 0.0
	_move_to_gather_target()

func _clear_gather_order():
	gather_target = null
	dropoff_target = null
	carried_resource = 0
	carried_resource_kind = "mineral"
	gather_timer = 0.0
	gather_nav_update_timer = 0.0
	gather_stuck_check_timer = 0.0
	gather_anim_timer = 0.0
	_stop_mineral_gather_voice()
	_set_excavation_hidden(false)
	_hide_carried_resource_sprite()

func start_build_order(target_position: Vector2, scene: PackedScene, _cells: Array, placement: Node, building_config: Dictionary = {}, append_order: bool = false):
	if not can_build or not scene:
		return false
	var site = null
	if placement and placement.has_method("create_construction_site"):
		site = placement.create_construction_site(target_position, null, _cells, building_config)
	if not is_instance_valid(site):
		_refund_build_config(building_config)
		if placement and placement.has_method("clear_build_cells") and not _cells.is_empty():
			placement.clear_build_cells(_cells)
		return false
	if site.has_method("set_reserved_builder"):
		site.set_reserved_builder(self)
	if site.has_method("set_waiting_for_builder"):
		site.set_waiting_for_builder(true)
	if current_state == State.BUILDING or append_order or not command_queue.is_empty():
		_enqueue_command({
			"type": "build_site",
			"site": site,
			"pos": target_position,
			"mineral_cost": int(building_config.get("mineral_cost", 0)),
			"gas_cost": int(building_config.get("gas_cost", 0))
		})
		return true
	if not append_order and not executing_queued_command:
		_clear_command_queue()
	_clear_gather_order()
	build_target_position = target_position
	build_scene = null
	build_placement = placement
	build_site = site
	build_cells.clear()
	build_config = building_config.duplicate()
	build_cost_pending_refund = false
	build_orbit_angle = randf() * TAU
	nav_agent.target_position = _get_build_approach_position(target_position)
	current_state = State.MOVING_TO_BUILD
	stuck_timer = 0.0
	last_pos = global_position
	return true

func get_build_order_load() -> int:
	var build_load := 0
	if current_state == State.MOVING_TO_BUILD or current_state == State.BUILDING:
		build_load += 1
	elif current_state != State.IDLE:
		build_load += 100
	for command in command_queue:
		if str(command.get("type", "")) == "build_site":
			build_load += 1
	return build_load

func resume_building_site(site: Node2D, append_order: bool = false, cost_config: Dictionary = {}):
	if not can_build or not is_instance_valid(site):
		return
	if site.has_method("can_be_built_by") and not site.can_be_built_by(self):
		return
	if append_order or current_state == State.BUILDING or (not executing_queued_command and not command_queue.is_empty()):
		_enqueue_command({"type": "build_site", "site": site, "pos": site.global_position})
		return
	if not executing_queued_command:
		_clear_command_queue()
	_clear_gather_order()
	build_target_position = site.global_position
	build_scene = null
	build_placement = null
	build_site = site
	build_cells.clear()
	build_config = cost_config.duplicate()
	build_cost_pending_refund = false
	build_orbit_angle = randf() * TAU
	nav_agent.target_position = _get_build_approach_position(build_target_position)
	current_state = State.MOVING_TO_BUILD
	stuck_timer = 0.0
	last_pos = global_position

func _clear_build_order():
	if is_instance_valid(build_site) and _is_cancelable_waiting_build_site_for_self(build_site):
		_refund_build_config(build_config)
		if build_site.has_method("cancel_construction"):
			build_site.cancel_construction()
	elif build_cost_pending_refund and build_scene != null and not is_instance_valid(build_site):
		_refund_pending_build_order()
	build_target_position = Vector2.ZERO
	build_scene = null
	build_placement = null
	build_site = null
	build_cells.clear()
	build_config.clear()
	build_cost_pending_refund = false

func _is_cancelable_waiting_build_site_for_self(site: Node2D) -> bool:
	if not _is_waiting_build_site_for_self(site):
		return false
	if "construction_started" in site and site.construction_started:
		return false
	if "construction_progress" in site and site.construction_progress > 0.0:
		return false
	return true

func _is_waiting_build_site_for_self(site: Node2D) -> bool:
	if not is_instance_valid(site):
		return false
	if not ("waiting_for_builder" in site) or not site.waiting_for_builder:
		return false
	if site.has_method("can_be_built_by") and not site.can_be_built_by(self):
		return false
	return true

func _refund_pending_build_order():
	if build_placement and build_placement.has_method("clear_build_cells") and not build_cells.is_empty():
		build_placement.clear_build_cells(build_cells)
	_refund_build_config(build_config)

func _refund_build_config(config: Dictionary):
	var mineral_cost = int(config.get("mineral_cost", 0))
	var gas_cost = int(config.get("gas_cost", 0))
	if mineral_cost <= 0 and gas_cost <= 0:
		return
	var hud = get_tree().current_scene.find_child("HUD", true, false) if get_tree().current_scene else null
	if hud and hud.has_method("add_resource"):
		hud.add_resource(mineral_cost, gas_cost)

func _get_build_approach_position(target_position: Vector2) -> Vector2:
	var rect := _get_build_rect_at(target_position)
	var rect_center := rect.get_center()
	var dir = rect_center.direction_to(global_position)
	if dir.length() < 0.1:
		dir = Vector2.RIGHT
	return _get_build_orbit_position(target_position, dir.angle())

func _process_moving_to_build(delta):
	if build_scene == null and not is_instance_valid(build_site):
		current_state = State.IDLE
		_start_next_queued_command()
		return
	if _escape_build_footprint_before_building():
		return
	if _is_at_build_approach_range() or nav_agent.is_navigation_finished():
		velocity = Vector2.ZERO
		if not is_instance_valid(build_site) and build_placement and build_placement.has_method("create_construction_site"):
			build_site = build_placement.create_construction_site(build_target_position, self, build_cells, build_config)
			build_cost_pending_refund = false
		if is_instance_valid(build_site):
			if build_site.has_method("begin_reserved_construction"):
				build_site.begin_reserved_construction(self)
			elif build_site.has_method("set_waiting_for_builder"):
				build_site.set_waiting_for_builder(false)
			if _escape_build_footprint_before_building():
				return
		current_state = State.BUILDING
		return
	_process_navigation_moving(delta)
	_check_if_stuck(delta)

func _process_building(delta):
	if not is_instance_valid(build_site):
		_clear_build_order()
		current_state = State.IDLE
		_play_unit_animation("stand_" + last_direction)
		_start_next_queued_command()
		return
	if "is_under_construction" in build_site and not build_site.is_under_construction:
		_clear_build_order()
		current_state = State.IDLE
		velocity = Vector2.ZERO
		_play_unit_animation("stand_" + last_direction)
		_start_next_queued_command()
		return
	build_orbit_angle += delta * 1.5
	var orbit_pos = _get_build_orbit_position(build_site.global_position, build_orbit_angle)
	if build_site.has_method("get_rect") and build_site.get_rect().has_point(global_position):
		orbit_pos = _get_nearest_build_orbit_position(build_site)
	var dir = global_position.direction_to(orbit_pos)
	if global_position.distance_to(orbit_pos) > 8.0:
		velocity = dir * speed * 0.55
		move_and_slide()
	else:
		velocity = Vector2.ZERO
	if build_site.has_method("add_construction_progress") and (_is_in_build_range(build_site) or _is_committed_to_build_site(build_site)):
		build_site.add_construction_progress(delta, self)
	_update_attack_animation(global_position.direction_to(build_site.global_position))

func on_construction_completed(site: Node2D):
	if not is_instance_valid(site):
		return
	var escape_pos := _get_safe_position_after_construction(site)
	global_position = escape_pos
	if nav_agent:
		nav_agent.target_position = escape_pos
	velocity = Vector2.ZERO
	stuck_timer = 0.0
	last_pos = global_position

func _get_safe_position_after_construction(site: Node2D) -> Vector2:
	if not site.has_method("get_rect"):
		return global_position
	var rect: Rect2 = site.get_rect()
	var center := rect.get_center()
	var base_dir := center.direction_to(global_position)
	if base_dir.length() < 0.1:
		base_dir = Vector2(0, 1)
	var base_angle := base_dir.angle()
	var radius: float = max(build_orbit_radius + 28.0, 56.0)
	var best_pos := _get_build_perimeter_position(rect, base_angle, radius)
	var best_dist: float = INF
	for i in range(16):
		var offset_index := int(ceil(float(i) / 2.0))
		var side := -1.0 if i % 2 == 0 else 1.0
		var angle := base_angle + side * offset_index * TAU / 16.0
		var candidate := _get_build_perimeter_position(rect, angle, radius)
		if not _is_safe_construction_escape_position(candidate, site):
			continue
		var dist := global_position.distance_squared_to(candidate)
		if dist < best_dist:
			best_dist = dist
			best_pos = candidate
	if best_dist < INF:
		return best_pos
	return _get_build_perimeter_position(rect, base_angle, radius + 32.0)

func _is_safe_construction_escape_position(pos: Vector2, completed_site: Node2D) -> bool:
	if completed_site.has_method("get_rect") and completed_site.get_rect().grow(12.0).has_point(pos):
		return false
	for obstacle in get_tree().get_nodes_in_group("Building") + get_tree().get_nodes_in_group("ResourceDeposit") + get_tree().get_nodes_in_group("Ruins"):
		if not is_instance_valid(obstacle) or not (obstacle is Node2D) or not obstacle.has_method("get_rect"):
			continue
		var rect: Rect2 = obstacle.get_rect().grow(obstacle_spacing + 8.0)
		if rect.has_point(pos):
			return false
	return true

func _is_in_build_range(site: Node2D) -> bool:
	if not is_instance_valid(site):
		return false
	if site.has_method("get_rect"):
		return site.get_rect().grow(build_orbit_radius + BUILD_PROGRESS_RANGE_PADDING).has_point(global_position)
	return global_position.distance_to(site.global_position) <= build_orbit_radius + BUILD_PROGRESS_RANGE_PADDING

func _is_committed_to_build_site(site: Node2D) -> bool:
	return current_state == State.BUILDING and is_instance_valid(site) and site == build_site

func _is_at_build_approach_range() -> bool:
	var rect := _get_build_rect_at(build_target_position)
	return not rect.has_point(global_position) and rect.grow(build_orbit_radius + BUILD_APPROACH_RANGE_PADDING).has_point(global_position)

func _get_build_orbit_position(bottom_center: Vector2, angle: float) -> Vector2:
	var rect := _get_build_rect_at(bottom_center)
	return _get_build_perimeter_position(rect, angle, build_orbit_radius)

func _get_build_perimeter_position(rect: Rect2, angle: float, margin: float) -> Vector2:
	var center := rect.get_center()
	var dir := Vector2(cos(angle), sin(angle))
	if absf(dir.x) < 0.001:
		dir.x = 0.001
	if absf(dir.y) < 0.001:
		dir.y = 0.001
	var half := rect.size * 0.5
	var edge_scale = min((half.x + margin) / absf(dir.x), (half.y + margin) / absf(dir.y))
	return center + dir.normalized() * edge_scale

func _get_nearest_build_orbit_position(site: Node2D) -> Vector2:
	var rect: Rect2 = site.get_rect()
	var center := rect.get_center()
	var dir := center.direction_to(global_position)
	if dir.length() < 0.1:
		dir = Vector2(0, 1)
	var angle := dir.angle()
	build_orbit_angle = angle
	return _get_build_orbit_position(site.global_position, angle)

func _push_out_of_build_rect(site: Node2D):
	if not is_instance_valid(site) or not site.has_method("get_rect"):
		return
	var rect: Rect2 = site.get_rect()
	if not rect.has_point(global_position):
		return
	global_position = _get_nearest_build_orbit_position(site)
	if nav_agent:
		nav_agent.target_position = global_position

func _escape_build_footprint_before_building() -> bool:
	var rect := _get_build_rect_at(build_target_position)
	if not rect.has_point(global_position):
		return false
	var escape_pos := _get_escape_position_for_build_rect(rect, build_target_position)
	global_position = escape_pos
	nav_agent.target_position = escape_pos
	velocity = Vector2.ZERO
	stuck_timer = 0.0
	last_pos = global_position
	return true

func _get_escape_position_for_build_rect(rect: Rect2, bottom_center: Vector2) -> Vector2:
	var center := rect.get_center()
	var dir := center.direction_to(global_position)
	if dir.length() < 0.1:
		dir = Vector2(0, 1)
	var angle := dir.angle()
	build_orbit_angle = angle
	return _get_build_orbit_position(bottom_center, angle)

func _get_build_rect_at(bottom_center: Vector2) -> Rect2:
	if is_instance_valid(build_site) and build_site.has_method("get_rect"):
		return build_site.get_rect()
	var footprint := Vector2(20 * 16, 8 * 16)
	if not build_config.is_empty() and build_config.has("footprint_tiles"):
		var tiles: Vector2i = build_config.get("footprint_tiles", Vector2i(20, 8))
		footprint = Vector2(tiles * 16)
	var contact_height: float = maxf(16.0, footprint.y * BUILD_CONTACT_HEIGHT_RATIO)
	return Rect2(bottom_center + Vector2(-footprint.x * 0.5, -contact_height), Vector2(footprint.x, contact_height))

func _move_to_gather_target():
	if not _is_valid_resource(gather_target):
		gather_target = _find_nearest_resource()
		if not _is_valid_resource(gather_target):
			_clear_gather_order()
			current_state = State.IDLE
			return
	nav_agent.target_position = _get_resource_approach_position(gather_target)
	gather_nav_update_timer = gather_nav_update_interval
	gather_stuck_check_timer = 0.0
	current_state = State.MOVING_TO_RESOURCE
	stuck_timer = 0.0
	last_pos = global_position

func _process_moving_to_resource(delta):
	if not _is_valid_resource(gather_target):
		_move_to_gather_target()
		return
	if _is_in_gather_range(gather_target):
		_begin_gathering()
		return
	gather_nav_update_timer -= delta
	if gather_nav_update_timer <= 0.0:
		nav_agent.target_position = _get_resource_approach_position(gather_target)
		gather_nav_update_timer = gather_nav_update_interval
	_process_navigation_moving(delta)
	if nav_agent.is_navigation_finished() and _is_in_loose_gather_range(gather_target):
		_begin_gathering()
		return
	_check_gather_stuck(delta)

func _begin_gathering():
	velocity = Vector2.ZERO
	gather_timer = 0.0
	gather_anim_timer = 0.0
	current_state = State.GATHERING
	if _get_resource_kind(gather_target) == "artifact":
		_set_excavation_hidden(true)
	else:
		_update_attack_animation(global_position.direction_to(gather_target.global_position))
		_start_mineral_gather_voice()

func _is_in_gather_range(resource: Node2D) -> bool:
	if not is_instance_valid(resource):
		return false
	if resource.has_method("get_rect"):
		return resource.get_rect().grow(gather_range * 0.45).has_point(global_position)
	return global_position.distance_squared_to(resource.global_position) <= gather_range * gather_range

func _is_in_loose_gather_range(resource: Node2D) -> bool:
	if not is_instance_valid(resource):
		return false
	if resource.has_method("get_rect"):
		return resource.get_rect().grow(gather_range * 0.75).has_point(global_position)
	return global_position.distance_squared_to(resource.global_position) <= pow(gather_range * 1.1, 2.0)

func _process_gathering(delta):
	if not _is_valid_resource(gather_target):
		_stop_mineral_gather_voice()
		_set_excavation_hidden(false)
		_move_to_gather_target()
		return
	velocity = Vector2.ZERO
	gather_timer += delta
	var resource_kind := _get_resource_kind(gather_target)
	var active_gather_time := _get_resource_gather_time(gather_target)
	if resource_kind == "artifact":
		_set_excavation_hidden(true)
	else:
		gather_anim_timer -= delta
		if gather_anim_timer <= 0.0:
			_update_attack_animation(global_position.direction_to(gather_target.global_position))
			if gather_target.has_method("play_gather_effect"):
				gather_target.play_gather_effect(global_position)
			gather_anim_timer = 0.25
	if gather_timer < active_gather_time:
		return
	_stop_mineral_gather_voice()
	_set_excavation_hidden(false)
	var mined = gather_target.take_resource(gather_amount) if gather_target.has_method("take_resource") else gather_amount
	if mined <= 0:
		_move_to_gather_target()
		return
	carried_resource = mined
	carried_resource_kind = resource_kind
	_update_carried_resource_sprite()
	dropoff_target = dropoff_target if is_instance_valid(dropoff_target) else _find_nearest_dropoff()
	if is_instance_valid(dropoff_target):
		nav_agent.target_position = _get_dropoff_approach_position(dropoff_target)
		gather_nav_update_timer = gather_nav_update_interval
		gather_stuck_check_timer = 0.0
		current_state = State.RETURNING_RESOURCE
	else:
		_deliver_resource()
		_move_to_gather_target()

func _process_returning_resource(delta):
	if not is_instance_valid(dropoff_target):
		dropoff_target = _find_nearest_dropoff()
	if is_instance_valid(dropoff_target):
		if _is_in_dropoff_range(dropoff_target):
			_deliver_resource()
			_move_to_gather_target()
			return
		gather_nav_update_timer -= delta
		if gather_nav_update_timer <= 0.0:
			nav_agent.target_position = _get_dropoff_approach_position(dropoff_target)
			gather_nav_update_timer = gather_nav_update_interval
		_process_navigation_moving(delta)
		_check_gather_stuck(delta)
	else:
		_deliver_resource()
		_move_to_gather_target()

func _deliver_resource():
	if carried_resource <= 0:
		return
	var hud = get_tree().current_scene.find_child("HUD", true, false) if get_tree().current_scene else null
	if hud and hud.has_method("add_resource"):
		if carried_resource_kind == "artifact":
			hud.add_resource(0, carried_resource)
		else:
			hud.add_resource(carried_resource, 0)
	carried_resource = 0
	carried_resource_kind = "mineral"
	_hide_carried_resource_sprite()

func _start_mineral_gather_voice():
	if mineral_gather_voice_active:
		return
	var manager = get_tree().get_first_node_in_group("UnitManager")
	if manager and manager.has_method("is_student_unit") and manager.is_student_unit(self) and manager.has_method("start_student_loop_voice"):
		mineral_gather_voice_active = manager.start_student_loop_voice("mineral", self)

func _stop_mineral_gather_voice():
	if not mineral_gather_voice_active:
		return
	mineral_gather_voice_active = false
	var manager = get_tree().get_first_node_in_group("UnitManager")
	if manager and manager.has_method("stop_student_loop_voice"):
		manager.stop_student_loop_voice("mineral")

func _create_carried_resource_sprite():
	if carried_resource_sprite:
		return
	carried_resource_sprite = Sprite2D.new()
	carried_resource_sprite.name = "CarriedResourceSprite"
	carried_resource_sprite.centered = true
	carried_resource_sprite.position = Vector2(8, -34)
	carried_resource_sprite.scale = Vector2(0.9, 0.9)
	carried_resource_sprite.z_index = 3
	carried_resource_sprite.visible = false
	add_child(carried_resource_sprite)

func _update_carried_resource_sprite():
	_create_carried_resource_sprite()
	carried_resource_sprite.texture = RELICS_CARRY_TEXTURE if carried_resource_kind == "artifact" else LAPIS_CARRY_TEXTURE
	carried_resource_sprite.visible = carried_resource > 0

func _hide_carried_resource_sprite():
	if carried_resource_sprite:
		carried_resource_sprite.visible = false

func _is_valid_resource(resource) -> bool:
	return is_instance_valid(resource) and resource.is_in_group("ResourceDeposit") and (not resource.has_method("is_depleted") or not resource.is_depleted())

func _get_resource_kind(resource) -> String:
	if is_instance_valid(resource) and resource.has_method("get_resource_kind"):
		return str(resource.get_resource_kind())
	if is_instance_valid(resource) and "resource_kind" in resource:
		return str(resource.resource_kind)
	return "mineral"

func _get_resource_gather_time(resource) -> float:
	if is_instance_valid(resource) and resource.has_method("get_gather_time"):
		var custom_time = float(resource.get_gather_time())
		if custom_time > 0.0:
			return custom_time
	return gather_time

func _set_excavation_hidden(is_hidden: bool):
	if hidden_for_excavation == is_hidden:
		return
	hidden_for_excavation = is_hidden
	visible = not is_hidden

func release_from_depleted_resource(resource: Node2D):
	if not is_instance_valid(resource) or gather_target != resource:
		return
	if current_state == State.RETURNING_RESOURCE or carried_resource > 0:
		return
	_set_excavation_hidden(false)
	_stop_mineral_gather_voice()
	_hide_carried_resource_sprite()
	gather_target = null
	gather_timer = 0.0
	gather_anim_timer = 0.0
	velocity = Vector2.ZERO
	current_state = State.IDLE
	if resource.has_method("get_rect"):
		var rect: Rect2 = resource.get_rect()
		if rect.grow(8.0).has_point(global_position):
			global_position = _get_resource_exit_position(rect)
	if nav_agent:
		nav_agent.target_position = global_position
	_play_unit_animation("stand_" + last_direction)

func _get_resource_exit_position(rect: Rect2) -> Vector2:
	var center := rect.get_center()
	var exit_dir := center.direction_to(global_position)
	if exit_dir.length() < 0.1:
		var angle := float(get_instance_id() % 16) * TAU / 16.0
		exit_dir = Vector2(cos(angle), sin(angle))
	var half := rect.size * 0.5
	var dir := exit_dir.normalized()
	var scale_x: float = (half.x + 28.0) / max(absf(dir.x), 0.001)
	var scale_y: float = (half.y + 28.0) / max(absf(dir.y), 0.001)
	return center + dir * min(scale_x, scale_y)

func _get_resource_approach_position(resource: Node2D) -> Vector2:
	if not is_instance_valid(resource):
		return global_position
	if resource.has_method("get_rect"):
		var rect: Rect2 = resource.get_rect()
		var center := rect.get_center()
		var dir := center.direction_to(global_position)
		if dir.length() < 0.1:
			dir = Vector2.RIGHT
		var far_point = center + dir.normalized() * max(rect.size.x, rect.size.y)
		var edge = far_point.clamp(rect.position, rect.position + rect.size)
		return edge + dir.normalized() * max(gather_range * 0.25, 18.0)
	var approach_dir = resource.global_position.direction_to(global_position)
	if approach_dir.length() < 0.1:
		approach_dir = Vector2.RIGHT
	return resource.global_position + approach_dir.normalized() * max(gather_range * 0.35, 28.0)

func _get_alternate_approach_position(center: Vector2, radius: float) -> Vector2:
	var base_angle := center.direction_to(global_position).angle()
	var turn := (float((reroute_attempt_count % 6) + 1) * PI / 3.0)
	var side := -1.0 if reroute_attempt_count % 2 == 0 else 1.0
	var angle := base_angle + turn * side
	return center + Vector2(cos(angle), sin(angle)) * radius

func _get_dropoff_approach_position(dropoff: Node2D) -> Vector2:
	if not is_instance_valid(dropoff):
		return global_position
	if dropoff.has_method("get_dropoff_rect") or dropoff.has_method("get_rect"):
		var rect: Rect2 = dropoff.call("get_dropoff_rect") if dropoff.has_method("get_dropoff_rect") else dropoff.get_rect()
		var nearest = global_position.clamp(rect.position, rect.position + rect.size)
		var rect_dir = nearest.direction_to(global_position)
		if rect_dir.length() < 0.1:
			rect_dir = rect.get_center().direction_to(global_position)
		if rect_dir.length() < 0.1:
			rect_dir = Vector2.DOWN
		return nearest + rect_dir.normalized() * max(dropoff_range * 0.35, 28.0)
	var approach_dir = dropoff.global_position.direction_to(global_position)
	if approach_dir.length() < 0.1:
		approach_dir = Vector2.RIGHT
	return dropoff.global_position + approach_dir.normalized() * max(dropoff_range * 0.6, 40.0)

func _get_alternate_dropoff_position(dropoff: Node2D) -> Vector2:
	if not is_instance_valid(dropoff):
		return global_position
	var center: Vector2 = dropoff.global_position
	var radius: float = max(dropoff_range * 0.75, 56.0)
	if dropoff.has_method("get_dropoff_rect") or dropoff.has_method("get_rect"):
		var rect: Rect2 = dropoff.call("get_dropoff_rect") if dropoff.has_method("get_dropoff_rect") else dropoff.get_rect()
		center = rect.get_center()
		radius = max(max(rect.size.x, rect.size.y) * 0.55 + dropoff_range * 0.4, 64.0)
	return _get_alternate_approach_position(center, radius)

func _is_in_dropoff_range(dropoff: Node2D) -> bool:
	if not is_instance_valid(dropoff):
		return false
	if dropoff.has_method("get_dropoff_rect") or dropoff.has_method("get_rect"):
		var rect: Rect2 = dropoff.call("get_dropoff_rect") if dropoff.has_method("get_dropoff_rect") else dropoff.get_rect()
		if rect.grow(dropoff_range * 0.5).has_point(global_position):
			return true
		var nearest = global_position.clamp(rect.position, rect.position + rect.size)
		var delivery_range := dropoff_range + 18.0
		return global_position.distance_squared_to(nearest) <= delivery_range * delivery_range
	return global_position.distance_squared_to(dropoff.global_position) <= dropoff_range * dropoff_range

func _check_gather_stuck(delta):
	gather_stuck_check_timer += delta
	if gather_stuck_check_timer < gather_stuck_check_interval:
		return
	_check_if_stuck(gather_stuck_check_timer)
	gather_stuck_check_timer = 0.0

func _get_attack_move_enemy(delta: float):
	attack_scan_timer -= delta
	if attack_scan_timer > 0.0:
		return null
	if is_in_group("Enemy"):
		attack_scan_timer = 0.65 + randf_range(0.0, 0.25)
	else:
		attack_scan_timer = 0.34 + randf_range(0.0, 0.18)
	return _find_closest_enemy()

func _apply_soft_separation(delta):
	if is_in_group("Enemy"):
		return
	if current_state == State.IDLE:
		return
	if current_state == State.MOVING_TO_RESOURCE or current_state == State.GATHERING or current_state == State.RETURNING_RESOURCE:
		return
	separation_update_timer -= delta
	if separation_update_timer <= 0.0:
		cached_separation_push = _calculate_soft_separation_push()
		separation_update_timer = SEPARATION_UPDATE_INTERVAL + randf_range(0.0, 0.06)
	if cached_separation_push != Vector2.ZERO:
		global_position += cached_separation_push * separation_strength * delta

func _calculate_soft_separation_push() -> Vector2:
	var push = Vector2.ZERO
	var radius_sq: float = separation_radius * separation_radius
	var checked := 0
	for other in _get_cached_units():
		if other == self or not is_instance_valid(other) or not (other is Node2D):
			continue
		var offset = global_position - other.global_position
		var dist_sq: float = offset.length_squared()
		if dist_sq > radius_sq:
			continue
		checked += 1
		if dist_sq > 0.01 and dist_sq < radius_sq:
			var dist := sqrt(dist_sq)
			push += offset.normalized() * ((separation_radius - dist) / separation_radius)
		if checked >= MAX_SEPARATION_CHECKS:
			break
	return push.normalized() if push != Vector2.ZERO else Vector2.ZERO

func _apply_obstacle_spacing(delta):
	if is_in_group("Enemy"):
		return
	if current_state == State.IDLE:
		return
	if current_state == State.BUILDING or current_state == State.GATHERING or current_state == State.MOVING_TO_RESOURCE or current_state == State.RETURNING_RESOURCE:
		return
	obstacle_update_timer -= delta
	if obstacle_update_timer <= 0.0:
		cached_obstacle_push = _calculate_obstacle_spacing_push()
		obstacle_update_timer = OBSTACLE_UPDATE_INTERVAL + randf_range(0.0, 0.08)
	if cached_obstacle_push != Vector2.ZERO:
		global_position += cached_obstacle_push * obstacle_spacing_strength * delta

func _calculate_obstacle_spacing_push() -> Vector2:
	var push = Vector2.ZERO
	var checked := 0
	for obstacle in _get_cached_obstacles():
		if not is_instance_valid(obstacle) or not (obstacle is Node2D) or not obstacle.has_method("get_rect"):
			continue
		if global_position.distance_squared_to(obstacle.global_position) > 90000.0:
			continue
		checked += 1
		var rect = obstacle.get_rect().grow(obstacle_spacing)
		if not rect.has_point(global_position):
			if checked >= MAX_OBSTACLE_CHECKS:
				break
			continue
		var closest = global_position.clamp(rect.position, rect.position + rect.size)
		var away = global_position - closest
		if away.length() < 0.1:
			away = obstacle.global_position.direction_to(global_position)
		if away.length() < 0.1:
			away = Vector2.RIGHT
		push += away.normalized()
		if checked >= MAX_OBSTACLE_CHECKS:
			break
	return push.normalized() if push != Vector2.ZERO else Vector2.ZERO

func _enqueue_command(command: Dictionary):
	command_queue.append(command)
	if current_state == State.IDLE:
		_start_next_queued_command()

func _clear_command_queue():
	for command in command_queue:
		if str(command.get("type", "")) != "build_site":
			continue
		var site = command.get("site", null)
		if is_instance_valid(site) and "waiting_for_builder" in site and site.waiting_for_builder and (not ("construction_started" in site) or not site.construction_started):
			_refund_build_command(command)
			if site.has_method("cancel_construction"):
				site.cancel_construction()
	command_queue.clear()

func _refund_build_command(command: Dictionary):
	var mineral_cost = int(command.get("mineral_cost", 0))
	var gas_cost = int(command.get("gas_cost", 0))
	if mineral_cost <= 0 and gas_cost <= 0:
		return
	var hud = get_tree().current_scene.find_child("HUD", true, false) if get_tree().current_scene else null
	if hud and hud.has_method("add_resource"):
		hud.add_resource(mineral_cost, gas_cost)

func _start_next_queued_command():
	if command_queue.is_empty() or current_state != State.IDLE:
		return
	var command = command_queue.pop_front()
	executing_queued_command = true
	match str(command.get("type", "")):
		"move":
			set_target(command.get("pos", global_position), false)
		"attack_move":
			set_attack_move(command.get("pos", global_position), false)
		"gather":
			start_gathering(command.get("resource", null), command.get("dropoff", null), false)
		"build_site":
			resume_building_site(command.get("site", null), false, {
				"mineral_cost": int(command.get("mineral_cost", 0)),
				"gas_cost": int(command.get("gas_cost", 0))
			})
	executing_queued_command = false

func _find_nearest_resource():
	var closest = null
	var min_dist = auto_find_resource_range * auto_find_resource_range
	for resource in get_tree().get_nodes_in_group("ResourceDeposit"):
		if _is_valid_resource(resource):
			var d = global_position.distance_squared_to(resource.global_position)
			if d < min_dist:
				min_dist = d
				closest = resource
	return closest

func _is_valid_attack_target(target) -> bool:
	if not is_instance_valid(target) or target == self:
		return false
	if not (target is Node2D):
		return false
	if not ("hp" in target) or target.hp <= 0:
		return false
	return target.is_in_group("Enemy") or target.is_in_group("Ally") or target.is_in_group("Building")

func _find_nearest_dropoff():
	var closest = null
	var min_dist = INF
	for dropoff in get_tree().get_nodes_in_group("ResourceDropoff"):
		if _is_valid_resource_dropoff(dropoff):
			var d = _get_dropoff_distance(dropoff, global_position)
			if d < min_dist:
				min_dist = d
				closest = dropoff
	return closest

func _get_dropoff_distance(dropoff: Node2D, from_pos: Vector2) -> float:
	if is_instance_valid(dropoff) and (dropoff.has_method("get_dropoff_rect") or dropoff.has_method("get_rect")):
		var rect: Rect2 = dropoff.call("get_dropoff_rect") if dropoff.has_method("get_dropoff_rect") else dropoff.get_rect()
		var nearest = from_pos.clamp(rect.position, rect.position + rect.size)
		return from_pos.distance_to(nearest)
	return from_pos.distance_to(dropoff.global_position) if is_instance_valid(dropoff) else INF

func _is_valid_resource_dropoff(dropoff) -> bool:
	if not is_instance_valid(dropoff) or not (dropoff is Node2D):
		return false
	if not dropoff.is_in_group("Building"):
		return false
	if "is_under_construction" in dropoff and dropoff.is_under_construction:
		return false
	return not ("accepts_resource_dropoff" in dropoff) or dropoff.accepts_resource_dropoff

func _die():
	if is_dying:
		return
	is_dying = true
	_stop_mineral_gather_voice()
	_release_population_on_death()
	var manager = get_tree().get_first_node_in_group("UnitManager")
	if manager and manager.has_method("is_student_unit") and manager.is_student_unit(self) and manager.has_method("play_student_voice"):
		manager.play_student_voice("death", self)
	if manager and manager.has_method("is_graduate_unit") and manager.is_graduate_unit(self) and manager.has_method("play_graduate_voice"):
		manager.play_graduate_voice("death", self)
	if manager and manager.has_method("is_professor_unit") and manager.is_professor_unit(self) and manager.has_method("play_professor_voice"):
		manager.play_professor_voice("death", self)
	if manager and manager.has_method("is_armi_unit") and manager.is_armi_unit(self) and manager.has_method("play_armi_voice"):
		manager.play_armi_voice("death", self)
	if is_in_group("Enemy") and manager and manager.has_method("play_enemy_voice"):
		manager.play_enemy_voice("death", self)
	_stop_professor_heal_voice()
	if current_state == State.BUILDING and is_instance_valid(build_site) and build_site.has_method("pause_construction"):
		build_site.pause_construction(self)
	_clear_command_queue()
	_clear_gather_order()
	_clear_build_order()
	attack_target = null
	velocity = Vector2.ZERO
	current_state = State.IDLE
	input_pickable = false
	collision_layer = 0
	collision_mask = 0
	if collision_shape:
		collision_shape.set_deferred("disabled", true)
	if is_in_group("Unit"): remove_from_group("Unit")
	if is_in_group("Ally"): remove_from_group("Ally")
	if is_in_group("Enemy"): remove_from_group("Enemy")
	hover_mode = false
	select_mode = false
	queue_redraw()
	
	manager = get_tree().get_first_node_in_group("UnitManager")
	if manager and "unit_selected" in manager:
		if manager.unit_selected.has(self):
			manager.unit_selected.erase(self)
			if manager.has_method("_refresh_command_ui"):
				manager._refresh_command_ui()

	await _play_die_and_fade()
	queue_free()

func _release_population_on_death():
	if not is_in_group("Ally") or population_cost <= 0:
		return
	var hud = get_tree().current_scene.find_child("HUD", true, false) if get_tree().current_scene else null
	if hud and hud.has_method("release_population"):
		hud.release_population(population_cost)

func _play_die_and_fade():
	if not sprite or not sprite.sprite_frames or not sprite.sprite_frames.has_animation("die"):
		await get_tree().create_timer(0.1).timeout
		return
	var should_flip_right = sprite.flip_h and last_direction.begins_with("side")
	sprite.flip_h = should_flip_right
	sprite.sprite_frames.set_animation_loop("die", false)
	sprite.play("die")
	await sprite.animation_finished
	await get_tree().create_timer(1.0).timeout
	var tween = create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 1.0)
	await tween.finished

func _find_closest_enemy():
	if not can_attack:
		return null
	var closest = null
	var min_dist_sq = detection_range * detection_range
	for target in _get_attack_scan_targets():
		if not _is_hostile_auto_target(target):
			continue
		var target_dist := _get_attack_target_distance(target)
		var d := target_dist * target_dist
		if d < min_dist_sq:
			min_dist_sq = d
			closest = target
	return closest

func _get_attack_scan_targets() -> Array:
	var manager = _get_unit_manager()
	if is_in_group("Enemy") and manager and manager.has_method("get_cached_ally_targets"):
		return manager.get_cached_ally_targets()
	if not is_in_group("Enemy") and manager and manager.has_method("get_cached_enemy_targets"):
		return manager.get_cached_enemy_targets()
	return _get_cached_units() + _get_cached_obstacles()

func _is_hostile_auto_target(target) -> bool:
	if not is_instance_valid(target) or target == self or not (target is Node2D):
		return false
	if not ("hp" in target) or target.hp <= 0:
		return false
	if is_in_group("Enemy"):
		return target.is_in_group("Ally")
	return target.is_in_group("Enemy")

func _process_auto_heal(_delta):
	if not can_auto_heal or max_mana <= 0 or mana <= 0:
		_stop_professor_heal_voice()
		return
	if heal_timer > 0.0:
		return
	var target = _find_heal_target()
	if not target:
		_stop_professor_heal_voice()
		return
	var missing_hp = target.max_hp - target.hp
	if missing_hp <= 0:
		_stop_professor_heal_voice()
		return
	target.hp = min(target.max_hp, target.hp + min(heal_per_mana, missing_hp))
	mana -= 1
	heal_timer = heal_cooldown
	heal_animation_timer = max(heal_cooldown * 0.8, 0.12)
	_start_professor_heal_voice()
	var target_dir := global_position.direction_to(target.global_position)
	_update_attack_animation(target_dir)
	if target.has_method("play_heal_effect"):
		target.play_heal_effect()

func _start_professor_heal_voice():
	if professor_heal_voice_active:
		return
	var manager = get_tree().get_first_node_in_group("UnitManager")
	if manager and manager.has_method("is_professor_unit") and manager.is_professor_unit(self) and manager.has_method("start_professor_loop_voice"):
		professor_heal_voice_active = manager.start_professor_loop_voice("heal", self)

func _stop_professor_heal_voice():
	if not professor_heal_voice_active:
		return
	professor_heal_voice_active = false
	var manager = get_tree().get_first_node_in_group("UnitManager")
	if manager and manager.has_method("is_professor_unit") and manager.is_professor_unit(self) and manager.has_method("stop_professor_loop_voice"):
		manager.stop_professor_loop_voice("heal")

func _process_heal_animation(delta: float):
	if heal_animation_timer <= 0.0:
		return
	heal_animation_timer -= delta
	if heal_animation_timer > 0.0:
		return
	if current_state == State.IDLE and sprite:
		_play_unit_animation("stand_" + last_direction)

func _play_unit_animation(animation_name: String):
	if not sprite:
		return
	if sprite.animation == animation_name and sprite.is_playing():
		return
	sprite.play(animation_name)

func play_heal_effect():
	var now := Time.get_ticks_msec()
	if now - last_heal_effect_msec < 120:
		return
	last_heal_effect_msec = now
	var particles := CPUParticles2D.new()
	particles.name = "HealEffect"
	particles.amount = 10
	particles.one_shot = true
	particles.lifetime = 0.45
	particles.explosiveness = 0.85
	particles.randomness = 0.55
	particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	particles.emission_sphere_radius = 6.0
	particles.direction = Vector2(0, -1)
	particles.spread = 55.0
	particles.initial_velocity_min = 12.0
	particles.initial_velocity_max = 34.0
	particles.gravity = Vector2(0, -12.0)
	particles.scale_amount_min = 1.6
	particles.scale_amount_max = 2.8
	particles.color = Color(0.25, 1.0, 0.25, 0.9)
	particles.position = Vector2(0, -24)
	particles.z_index = 20
	add_child(particles)
	particles.emitting = true
	await get_tree().create_timer(0.7).timeout
	if is_instance_valid(particles):
		particles.queue_free()

func play_bullet_hit_effect():
	var now := Time.get_ticks_msec()
	if now - last_bullet_hit_effect_msec < 80:
		return
	last_bullet_hit_effect_msec = now
	var particles := CPUParticles2D.new()
	particles.name = "BulletHitEffect"
	particles.amount = 28
	particles.one_shot = true
	particles.lifetime = 0.5
	particles.explosiveness = 0.95
	particles.randomness = 0.8
	particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	particles.emission_sphere_radius = 9.0
	particles.direction = Vector2(0, -1)
	particles.spread = 170.0
	particles.initial_velocity_min = 28.0
	particles.initial_velocity_max = 76.0
	particles.gravity = Vector2(0, 34.0)
	particles.scale_amount_min = 3.2
	particles.scale_amount_max = 6.0
	particles.color = Color(1.0, 0.72, 0.0, 1.0)
	particles.position = Vector2(0, -22)
	particles.z_index = 21
	add_child(particles)
	particles.emitting = true
	await get_tree().create_timer(0.8).timeout
	if is_instance_valid(particles):
		particles.queue_free()

func _process_mana_regen(delta: float):
	if max_mana <= 0 or mana >= max_mana or mana_regen_per_second <= 0.0:
		return
	mana_regen_progress += mana_regen_per_second * delta
	var regen_amount := int(floor(mana_regen_progress))
	if regen_amount <= 0:
		return
	mana_regen_progress -= regen_amount
	mana = min(max_mana, mana + regen_amount)

func _find_heal_target():
	var best_target = null
	var best_missing = 0
	var range_sq = heal_range * heal_range
	var heal_candidates: Array = []
	var manager = _get_unit_manager()
	if manager and manager.has_method("get_cached_ally_targets"):
		heal_candidates = manager.get_cached_ally_targets()
	else:
		heal_candidates = _get_cached_units()
	for unit in heal_candidates:
		if not is_instance_valid(unit) or unit == self or not unit.is_in_group("Ally"):
			continue
		if not unit.is_in_group("Unit"):
			continue
		if not ("hp" in unit and "max_hp" in unit) or unit.hp >= unit.max_hp:
			continue
		if global_position.distance_squared_to(unit.global_position) > range_sq:
			continue
		var missing = int(unit.max_hp - unit.hp)
		if missing > best_missing:
			best_missing = missing
			best_target = unit
	return best_target

func _update_facing_direction(dir: Vector2):
	if dir.length() < 0.1: return
	var angle_deg = rad_to_deg(dir.angle())
	sprite.flip_h = false
	if angle_deg > -112.5 and angle_deg <= -67.5:
		last_direction = "back"
	elif angle_deg > 67.5 and angle_deg <= 112.5:
		last_direction = "front"
	elif angle_deg > -157.5 and angle_deg <= -112.5:
		last_direction = "sideback"
	elif angle_deg > -67.5 and angle_deg <= -22.5:
		last_direction = "sideback"; sprite.flip_h = true
	elif angle_deg > 112.5 or angle_deg <= -157.5:
		last_direction = "sidefront"
	elif angle_deg > 22.5 and angle_deg <= 67.5:
		last_direction = "sidefront"; sprite.flip_h = true
	elif angle_deg > -22.5 and angle_deg <= 22.5:
		last_direction = "sidefront"; sprite.flip_h = true
	else:
		last_direction = "sidefront"

func _update_animation(dir: Vector2):
	if dir.length() < 0.1: return
	var angle_deg = rad_to_deg(dir.angle())
	sprite.flip_h = false
	
	if angle_deg > -112.5 and angle_deg <= -67.5:
		last_direction = "back"; _play_unit_animation("run_back")
	elif angle_deg > 67.5 and angle_deg <= 112.5:
		last_direction = "front"; _play_unit_animation("run_front")
	elif angle_deg > -157.5 and angle_deg <= -112.5:
		last_direction = "sideback"; _play_unit_animation("run_sideback")
	elif angle_deg > -67.5 and angle_deg <= -22.5:
		last_direction = "sideback"; _play_unit_animation("run_sideback"); sprite.flip_h = true
	elif angle_deg > 112.5 or angle_deg <= -157.5:
		last_direction = "sidefront"; _play_unit_animation("run_sidefront")
	elif angle_deg > 22.5 and angle_deg <= 67.5:
		last_direction = "sidefront"; _play_unit_animation("run_sidefront"); sprite.flip_h = true
	elif angle_deg > -22.5 and angle_deg <= 22.5:
		last_direction = "sidefront"; _play_unit_animation("run_sidefront"); sprite.flip_h = true
	else:
		last_direction = "sidefront"; _play_unit_animation("run_sidefront")

func _update_attack_animation(dir: Vector2):
	if dir.length() < 0.1: return
	var angle_deg = rad_to_deg(dir.angle())
	sprite.flip_h = false
	
	if angle_deg > -112.5 and angle_deg <= -67.5:
		last_direction = "back"; _play_unit_animation("attack_back")
	elif angle_deg > 67.5 and angle_deg <= 112.5:
		last_direction = "front"; _play_unit_animation("attack_front")
	elif angle_deg > -157.5 and angle_deg <= -112.5:
		last_direction = "sideback"; _play_unit_animation("attack_sideback")
	elif angle_deg > -67.5 and angle_deg <= -22.5:
		last_direction = "sideback"; _play_unit_animation("attack_sideback"); sprite.flip_h = true
	elif angle_deg > 112.5 or angle_deg <= -157.5:
		last_direction = "sidefront"; _play_unit_animation("attack_sidefront")
	elif angle_deg > 22.5 and angle_deg <= 67.5:
		last_direction = "sidefront"; _play_unit_animation("attack_sidefront"); sprite.flip_h = true
	elif angle_deg > -22.5 and angle_deg <= 22.5:
		last_direction = "sidefront"; _play_unit_animation("attack_sidefront"); sprite.flip_h = true
	else:
		last_direction = "sidefront"; _play_unit_animation("attack_sidefront")

func _draw():
	var texture = sprite.sprite_frames.get_frame_texture(sprite.animation, sprite.frame)
	if not texture: return
	var size = texture.get_size() * sprite.global_scale
	var radius = size.x / 2.0 * 0.75
	var circle_offset = Vector2(0, -3)
	
	if not select_mode and hover_mode:
		draw_set_transform(circle_offset, 0, Vector2(1.0, 0.5))
		draw_arc(Vector2.ZERO, radius, 0, TAU, 40, Color(1.0, 0.95, 0.0, 1.0), 4.5, true)
		draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
	
	var bar_width = size.x * 0.9
	var bar_height = 6.0
	
	if select_mode:
		draw_set_transform(circle_offset, 0, Vector2(1.0, 0.5))
		draw_arc(Vector2.ZERO, radius, 0, TAU, 40, Color(0.0, 1.0, 0.0, 0.9), 4.5, true)
	
	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
	if not select_mode and hp >= max_hp:
		return
	var bar_pos = Vector2(-bar_width / 2, 4.0)
	var health_ratio = float(hp) / float(max_hp)
	var bar_color = Color.RED.lerp(Color.GREEN, health_ratio)
	if max_mana > 0:
		var mana_ratio = float(mana) / float(max(max_mana, 1))
		var mana_height := 3.0
		var mana_pos = bar_pos + Vector2(0, -mana_height - 2.0)
		draw_rect(Rect2(mana_pos, Vector2(bar_width, mana_height)), Color(0.05, 0.05, 0.12, 0.9))
		draw_rect(Rect2(mana_pos, Vector2(bar_width * mana_ratio, mana_height)), Color(0.15, 0.35, 1.0))
		draw_rect(Rect2(mana_pos, Vector2(bar_width, mana_height)), Color.BLACK, false, 1.0)
	
	draw_rect(Rect2(bar_pos, Vector2(bar_width, bar_height)), Color.WHITE)
	draw_rect(Rect2(bar_pos, Vector2(bar_width * health_ratio, bar_height)), bar_color)
	_draw_health_grid(bar_pos, bar_width, bar_height) 
	draw_rect(Rect2(bar_pos, Vector2(bar_width, bar_height)), Color.BLACK, false, 1.0)

func _draw_health_grid(bar_pos: Vector2, bar_width: float, bar_height: float):
	var grid_count = floor(max_hp / 10.0)
	if grid_count > 1:
		var segment_width = bar_width / grid_count
		for i in range(1, int(grid_count)):
			var line_x = bar_pos.x + (i * segment_width)
			var start_point = Vector2(line_x, bar_pos.y)
			var end_point = Vector2(line_x, bar_pos.y + bar_height)
			draw_line(start_point, end_point, Color(0, 0, 0, 0.4), 1.0)

func select():
	select_mode = true
	queue_redraw()

func deselect():
	select_mode = false
	queue_redraw()

func set_selected(value: bool):
	if value: select()
	else: deselect()

func get_rect() -> Rect2:
	if not sprite.sprite_frames: return Rect2()
	var texture = sprite.sprite_frames.get_frame_texture(sprite.animation, sprite.frame)
	if not texture: return Rect2()
	var size = texture.get_size() * sprite.global_scale
	var start_x: float = global_position.x - (size.x / 2.0)
	var start_y: float = global_position.y - (size.y / 2.0)
	return Rect2(start_x, start_y, float(size.x), float(size.y))
