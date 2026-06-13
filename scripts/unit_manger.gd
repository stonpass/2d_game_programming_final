extends Node2D

# CommandMode는 오직 "플레이어의 입력 대기 상태(UI 버튼 클릭 등)"만 나타냅니다.
enum CommandMode { NONE, MOVE, ATTACK, GATHER }
var current_command = CommandMode.NONE
const MOUSE_CLICK_SOUND: AudioStream = preload("res://assets/muic/mouse_cl.mp3")
const UI_ALERT_SOUNDS := {
	"mineral": "res://assets/muic/tadErr00.wav",
	"gas": "res://assets/muic/tadErr01.wav",
	"population": "res://assets/muic/tadErr02.wav",
	"upgrade_complete": "res://assets/muic/tadUPD06.wav",
	"building_under_attack": "res://assets/muic/tadUpd00.wav",
	"unit_under_attack": "res://assets/muic/tadUpd01.wav"
}

const MOVE_DESTINATION_TEXTURE: Texture2D = preload("res://캐릭터 폴더/mouse/mouse_point.png")
const ATTACK_DESTINATION_TEXTURE: Texture2D = preload("res://캐릭터 폴더/mouse/mouse_point_attak.png")

# --- 설정 변수 ---
var unit_selected: Array = []  
var selected_rect: Rect2       
var spacing: float = 40.0      
var move_destination_marker: Sprite2D = null
var attack_destination_marker: Sprite2D = null
var mouse_click_player: AudioStreamPlayer
var student_voice_player: AudioStreamPlayer
var student_loop_voice_player: AudioStreamPlayer
var graduate_voice_player: AudioStreamPlayer
var professor_voice_player: AudioStreamPlayer
var professor_loop_voice_player: AudioStreamPlayer
var armi_voice_player: AudioStreamPlayer
var ui_alert_player: AudioStreamPlayer
var active_loop_voice_type := ""
var active_professor_loop_voice_type := ""
var student_loop_voice_counts := {}
var professor_loop_voice_counts := {}
var active_attack_voice_counts := {}
var performance_cache_timer: float = 0.0
var cached_units: Array = []
var cached_enemies: Array = []
var cached_obstacles: Array = []
var cached_ally_targets: Array = []
var cached_enemy_targets: Array = []
var upgrade_levels := {"body": 0, "power": 0, "student": 0, "m_student": 0, "professor": 0, "armi": 0}
var upgrades_in_progress := {}

const UPGRADE_TIME := 60.0
const MAX_ATTACK_VOICES_PER_KIND := 5
const ATTACK_ALERT_COOLDOWN_MSEC := 10000
const MINIMAP_ATTACK_FLASH_MSEC := 1200
const MINIMAP_ATTACK_FLASH_INTERVAL_MSEC := 300
const OLD_ATTACK_MSEC := -1000000
var last_allied_building_attack_msec: int = OLD_ATTACK_MSEC
var last_allied_unit_attack_msec: int = OLD_ATTACK_MSEC
var minimap_attack_marks := {}
var attack_button_latched := false

# --- 더블 클릭 판정용 변수 ---
var is_double_clicking: bool = false
var last_click_time: float = 0.0
var last_clicked_unit: Node = null
const DOUBLE_CLICK_DELAY: float = 0.25 

func _ready():
	add_to_group("UnitManager")
	mouse_click_player = AudioStreamPlayer.new()
	mouse_click_player.name = "MouseClickSound"
	mouse_click_player.stream = MOUSE_CLICK_SOUND
	add_child(mouse_click_player)
	student_voice_player = AudioStreamPlayer.new()
	student_voice_player.name = "StudentVoiceSound"
	add_child(student_voice_player)
	student_loop_voice_player = AudioStreamPlayer.new()
	student_loop_voice_player.name = "StudentLoopVoiceSound"
	student_loop_voice_player.finished.connect(_on_student_loop_voice_finished)
	add_child(student_loop_voice_player)
	graduate_voice_player = AudioStreamPlayer.new()
	graduate_voice_player.name = "GraduateVoiceSound"
	add_child(graduate_voice_player)
	professor_voice_player = AudioStreamPlayer.new()
	professor_voice_player.name = "ProfessorVoiceSound"
	add_child(professor_voice_player)
	professor_loop_voice_player = AudioStreamPlayer.new()
	professor_loop_voice_player.name = "ProfessorLoopVoiceSound"
	professor_loop_voice_player.volume_db = linear_to_db(0.3)
	professor_loop_voice_player.finished.connect(_on_professor_loop_voice_finished)
	add_child(professor_loop_voice_player)
	armi_voice_player = AudioStreamPlayer.new()
	armi_voice_player.name = "ArmiVoiceSound"
	add_child(armi_voice_player)
	ui_alert_player = AudioStreamPlayer.new()
	ui_alert_player.name = "UIAlertSound"
	add_child(ui_alert_player)

func play_mouse_click_sound():
	if not mouse_click_player:
		return
	mouse_click_player.stop()
	mouse_click_player.play()

func play_student_voice(voice_type: String, source_unit: Node = null):
	if not student_voice_player:
		return
	if source_unit and not _is_node_in_camera_view(source_unit):
		return
	if student_voice_player.playing:
		return
	var candidates := _get_student_voice_paths(voice_type)
	var available: Array[String] = []
	for path in candidates:
		if ResourceLoader.exists(path):
			available.append(path)
	if available.is_empty():
		return
	var stream = load(available.pick_random())
	if not stream:
		return
	student_voice_player.stream = stream
	student_voice_player.play()

func play_graduate_voice(voice_type: String, source_unit: Node = null):
	if not graduate_voice_player:
		return
	if source_unit and not _is_node_in_camera_view(source_unit):
		return
	if voice_type == "hit":
		_play_unit_voice_one_shot(_get_graduate_voice_paths(voice_type), 0.3, source_unit, "graduate_hit")
		return
	if graduate_voice_player.playing:
		return
	var candidates := _get_graduate_voice_paths(voice_type)
	var available: Array[String] = []
	for path in candidates:
		if ResourceLoader.exists(path):
			available.append(path)
	if available.is_empty():
		return
	var stream = load(available.pick_random())
	if not stream:
		return
	graduate_voice_player.stream = stream
	graduate_voice_player.play()

func play_professor_voice(voice_type: String, source_unit: Node = null):
	if not professor_voice_player:
		return
	if source_unit and not _is_node_in_camera_view(source_unit):
		return
	if professor_voice_player.playing:
		return
	_play_unit_voice_from_paths(professor_voice_player, _get_professor_voice_paths(voice_type))

func play_armi_voice(voice_type: String, source_unit: Node = null):
	if not armi_voice_player:
		return
	if source_unit and not _is_node_in_camera_view(source_unit):
		return
	if voice_type == "fire":
		_play_unit_voice_one_shot(_get_armi_voice_paths(voice_type), 0.3, source_unit, "armi_fire")
		return
	if armi_voice_player.playing:
		return
	_play_unit_voice_from_paths(armi_voice_player, _get_armi_voice_paths(voice_type))

func play_enemy_voice(voice_type: String, source_unit: Node = null):
	match voice_type:
		"death":
			_play_unit_voice_one_shot(["res://assets/muic/적/ZZeDth00.wav"], 1.0, source_unit, "enemy_death")
		"fire":
			_play_unit_voice_one_shot(["res://assets/muic/적/zguFir00.wav"], 1.0, source_unit, "enemy_fire")

func play_ui_alert(alert_type: String):
	if not ui_alert_player or not UI_ALERT_SOUNDS.has(alert_type):
		return
	var path := str(UI_ALERT_SOUNDS[alert_type])
	if not ResourceLoader.exists(path):
		return
	var stream = load(path)
	if not stream:
		return
	ui_alert_player.stop()
	ui_alert_player.stream = stream
	ui_alert_player.play(0.0)

func notify_ally_under_attack(target: Node, kind: String):
	if not is_instance_valid(target):
		return
	var now := Time.get_ticks_msec()
	minimap_attack_marks[target.get_instance_id()] = now
	if kind == "building":
		if now - last_allied_building_attack_msec >= ATTACK_ALERT_COOLDOWN_MSEC:
			_show_hud_notice("건물이 공격받고 있습니다")
			play_ui_alert("building_under_attack")
		last_allied_building_attack_msec = now
	elif kind == "unit":
		if now - last_allied_unit_attack_msec >= ATTACK_ALERT_COOLDOWN_MSEC:
			_show_hud_notice("아군이 공격받고 있습니다")
			play_ui_alert("unit_under_attack")
		last_allied_unit_attack_msec = now

func is_minimap_attack_flashing(target: Node) -> bool:
	if not is_instance_valid(target):
		return false
	var target_id := target.get_instance_id()
	if not minimap_attack_marks.has(target_id):
		return false
	var now := Time.get_ticks_msec()
	var elapsed := now - int(minimap_attack_marks[target_id])
	if elapsed > MINIMAP_ATTACK_FLASH_MSEC:
		minimap_attack_marks.erase(target_id)
		return false
	return true

func get_minimap_ally_attack_color(target: Node) -> Color:
	if not is_minimap_attack_flashing(target):
		return Color.GREEN
	var elapsed := Time.get_ticks_msec() - int(minimap_attack_marks[target.get_instance_id()])
	var flash_step := int(floori(float(elapsed) / float(MINIMAP_ATTACK_FLASH_INTERVAL_MSEC)))
	return Color.RED if flash_step % 2 == 0 else Color.GREEN

func _play_unit_voice_from_paths(player: AudioStreamPlayer, candidates: Array[String]):
	var available: Array[String] = []
	for path in candidates:
		if ResourceLoader.exists(path):
			available.append(path)
	if available.is_empty():
		return
	var stream = load(available.pick_random())
	if not stream:
		return
	player.stream = stream
	player.play()

func _play_unit_voice_one_shot(candidates: Array[String], volume_scale: float = 1.0, source_unit: Node = null, limit_key: String = ""):
	if source_unit and not _is_node_in_camera_view(source_unit):
		return
	if not limit_key.is_empty():
		var active_count := int(active_attack_voice_counts.get(limit_key, 0))
		if active_count >= MAX_ATTACK_VOICES_PER_KIND:
			return
	var available: Array[String] = []
	for path in candidates:
		if ResourceLoader.exists(path):
			available.append(path)
	if available.is_empty():
		return
	var stream = load(available.pick_random())
	if not stream:
		return
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.volume_db = linear_to_db(volume_scale)
	if not limit_key.is_empty():
		active_attack_voice_counts[limit_key] = int(active_attack_voice_counts.get(limit_key, 0)) + 1
		player.finished.connect(_on_limited_attack_voice_finished.bind(limit_key))
	player.finished.connect(player.queue_free)
	add_child(player)
	player.play()

func _on_limited_attack_voice_finished(limit_key: String):
	active_attack_voice_counts[limit_key] = max(0, int(active_attack_voice_counts.get(limit_key, 0)) - 1)

func start_student_loop_voice(voice_type: String, source_unit: Node = null):
	if not student_loop_voice_player:
		return false
	if source_unit and not _is_node_in_camera_view(source_unit):
		return false
	student_loop_voice_counts[voice_type] = int(student_loop_voice_counts.get(voice_type, 0)) + 1
	if active_loop_voice_type == voice_type and student_loop_voice_player.playing:
		return true
	active_loop_voice_type = voice_type
	_play_next_student_loop_voice()
	return true

func stop_student_loop_voice(voice_type: String = ""):
	if not student_loop_voice_player:
		return
	if not voice_type.is_empty() and active_loop_voice_type != voice_type:
		return
	if not voice_type.is_empty():
		var next_count = max(0, int(student_loop_voice_counts.get(voice_type, 0)) - 1)
		if next_count > 0:
			student_loop_voice_counts[voice_type] = next_count
			return
		student_loop_voice_counts.erase(voice_type)
	else:
		student_loop_voice_counts.clear()
	active_loop_voice_type = ""
	student_loop_voice_player.stop()

func _on_student_loop_voice_finished():
	if active_loop_voice_type.is_empty():
		return
	_play_next_student_loop_voice()

func _play_next_student_loop_voice():
	if active_loop_voice_type.is_empty():
		return
	var candidates := _get_student_voice_paths(active_loop_voice_type)
	var available: Array[String] = []
	for path in candidates:
		if ResourceLoader.exists(path):
			available.append(path)
	if available.is_empty():
		return
	var stream = load(available.pick_random())
	if not stream:
		return
	student_loop_voice_player.stop()
	student_loop_voice_player.stream = stream
	student_loop_voice_player.volume_db = linear_to_db(0.3 if active_loop_voice_type == "mineral" else 1.0)
	student_loop_voice_player.play()

func start_professor_loop_voice(voice_type: String, source_unit: Node = null):
	if not professor_loop_voice_player:
		return false
	if source_unit and not _is_node_in_camera_view(source_unit):
		return false
	professor_loop_voice_counts[voice_type] = int(professor_loop_voice_counts.get(voice_type, 0)) + 1
	if active_professor_loop_voice_type == voice_type and professor_loop_voice_player.playing:
		return true
	active_professor_loop_voice_type = voice_type
	if not professor_loop_voice_player.playing:
		_play_next_professor_loop_voice()
	return true

func stop_professor_loop_voice(voice_type: String = ""):
	if not professor_loop_voice_player:
		return
	if not voice_type.is_empty() and active_professor_loop_voice_type != voice_type:
		return
	if not voice_type.is_empty():
		var next_count = max(0, int(professor_loop_voice_counts.get(voice_type, 0)) - 1)
		if next_count > 0:
			professor_loop_voice_counts[voice_type] = next_count
			return
		professor_loop_voice_counts.erase(voice_type)
	else:
		professor_loop_voice_counts.clear()
	active_professor_loop_voice_type = ""
	professor_loop_voice_player.stop()

func _on_professor_loop_voice_finished():
	if active_professor_loop_voice_type.is_empty():
		return
	_play_next_professor_loop_voice()

func _play_next_professor_loop_voice():
	if active_professor_loop_voice_type.is_empty():
		return
	var candidates := _get_professor_voice_paths(active_professor_loop_voice_type)
	var available: Array[String] = []
	for path in candidates:
		if ResourceLoader.exists(path):
			available.append(path)
	if available.is_empty():
		return
	var stream = load(available.pick_random())
	if not stream:
		return
	professor_loop_voice_player.stop()
	professor_loop_voice_player.stream = stream
	professor_loop_voice_player.play()

func _get_student_voice_paths(voice_type: String) -> Array[String]:
	var base := "res://assets/muic/학생/"
	match voice_type:
		"death":
			return [base + "TSCDth00.wav"]
		"error":
			return [base + "TSCErr00.wav", base + "TSCErr01.wav"]
		"move":
			return [
				base + "TSCPss00.wav",
				base + "TSCPss01.wav",
				base + "TSCPss02.wav",
				base + "TSCPss03.wav",
				base + "TSCPss04.wav",
				base + "TSCPss05.wav",
				base + "TSCPss50.wav"
			]
		"ready":
			return [base + "TSCRdy00.wav"]
		"complete":
			return [base + "TSCUpd00.wav"]
		"mineral":
			return [base + "TSCMin00.wav", base + "TSCMin01.wav"]
		"what":
			return [
				base + "TSCWht00.wav",
				base + "TSCWht01.wav",
				base + "TSCWht02.wav",
				base + "TSCWht03.wav"
			]
		"yes":
			return [
				base + "TSCYes00.wav",
				base + "TSCYes01.wav",
				base + "TSCYes02.wav",
				base + "TSCYes03.wav"
			]
	return []

func _get_graduate_voice_paths(voice_type: String) -> Array[String]:
	var base := "res://assets/muic/대학원생/"
	match voice_type:
		"death":
			return [base + "pzeDth00.wav"]
		"hit":
			return [base + "pzeHit00.wav"]
		"move":
			return [
				base + "PZePss00.wav",
				base + "PZePss01.wav",
				base + "PZePss02.wav"
			]
		"ready":
			return [base + "pzeRdy00.wav"]
		"what":
			return [
				base + "PZeWht00.wav",
				base + "PZeWht01.wav",
				base + "PZeWht02.wav",
				base + "PZeWht03.wav"
			]
		"yes":
			return [
				base + "PZeYes00.wav",
				base + "PZeYes01.wav",
				base + "PZeYes02.wav",
				base + "PZeYes03.wav"
			]
	return []

func _get_professor_voice_paths(voice_type: String) -> Array[String]:
	var base := "res://assets/muic/교수/"
	match voice_type:
		"death":
			return [base + "TMdDth00.wav"]
		"heal":
			return [base + "Miopia1.wav"]
		"move":
			return [
				base + "TMdPss00.wav",
				base + "TMdPss01.wav",
				base + "TMdPss02.wav",
				base + "TMdPss03.wav",
				base + "TMdPss04.wav",
				base + "TMdPss05.wav",
				base + "TMdPss06.wav"
			]
		"ready":
			return [base + "TMdRdy00.wav"]
		"what":
			return [
				base + "TMdWht00.wav",
				base + "TMdWht01.wav",
				base + "TMdWht02.wav",
				base + "TMdWht03.wav"
			]
		"yes":
			return [
				base + "TMdYes00.wav",
				base + "TMdYes01.wav",
				base + "TMdYes02.wav",
				base + "TMdYes03.wav"
			]
	return []

func _get_armi_voice_paths(voice_type: String) -> Array[String]:
	var base := "res://assets/muic/예비군/"
	match voice_type:
		"death":
			return [base + "TMaDth00.wav", base + "TMaDth01.wav"]
		"fire":
			return [base + "TMaFir00.wav"]
		"move":
			return [
				base + "TMaPss00.wav",
				base + "TMaPss01.wav",
				base + "TMaPss02.wav",
				base + "TMaPss03.wav",
				base + "TMaPss04.wav",
				base + "TMaPss05.wav",
				base + "TMaPss06.wav"
			]
		"ready":
			return [base + "TMaRdy00.wav"]
		"what":
			return [
				base + "TMaWht00.wav",
				base + "TMaWht01.wav",
				base + "TMaWht02.wav",
				base + "TMaWht03.wav"
			]
		"yes":
			return [
				base + "TMaYes00.wav",
				base + "TMaYes01.wav",
				base + "TMaYes02.wav",
				base + "TMaYes03.wav"
			]
	return []

func is_student_unit(unit) -> bool:
	if not is_instance_valid(unit):
		return false
	var scene_path := str(unit.scene_file_path if "scene_file_path" in unit else "")
	if scene_path.ends_with("/student.tscn") or scene_path == "student.tscn":
		return true
	return "unit_name" in unit and str(unit.unit_name).strip_edges() == "학생"

func is_graduate_unit(unit) -> bool:
	if not is_instance_valid(unit):
		return false
	var scene_path := str(unit.scene_file_path if "scene_file_path" in unit else "")
	if scene_path.ends_with("graduate_student.tscn"):
		return true
	return "unit_name" in unit and str(unit.unit_name).strip_edges() == "대학원생"

func is_professor_unit(unit) -> bool:
	if not is_instance_valid(unit):
		return false
	var scene_path := str(unit.scene_file_path if "scene_file_path" in unit else "")
	return scene_path.ends_with("professor.tscn")

func is_armi_unit(unit) -> bool:
	if not is_instance_valid(unit):
		return false
	var scene_path := str(unit.scene_file_path if "scene_file_path" in unit else "")
	return scene_path.ends_with("armi.tscn")

func _selected_has_student() -> bool:
	for selected in unit_selected:
		if is_student_unit(selected):
			return true
	return false

func _selected_has_graduate() -> bool:
	for selected in unit_selected:
		if is_graduate_unit(selected):
			return true
	return false

func _selected_has_professor() -> bool:
	for selected in unit_selected:
		if is_professor_unit(selected):
			return true
	return false

func _selected_has_armi() -> bool:
	for selected in unit_selected:
		if is_armi_unit(selected):
			return true
	return false

func _play_dominant_selected_voice(voice_type: String):
	var counts := {"student": 0, "graduate": 0, "professor": 0, "armi": 0}
	var representative := {}
	for selected in unit_selected:
		if not is_instance_valid(selected) or not selected is Node2D:
			continue
		if not selected.is_in_group("Ally") or not _is_node_in_camera_view(selected):
			continue
		var voice_kind := _get_unit_voice_kind(selected)
		if voice_kind.is_empty():
			continue
		counts[voice_kind] = int(counts.get(voice_kind, 0)) + 1
		if not representative.has(voice_kind):
			representative[voice_kind] = selected
	var best_kind := ""
	var best_count := 0
	for kind in ["student", "graduate", "professor", "armi"]:
		var count := int(counts.get(kind, 0))
		if count > best_count:
			best_count = count
			best_kind = kind
	if best_kind.is_empty():
		return
	var source_unit = representative.get(best_kind, null)
	match best_kind:
		"student":
			play_student_voice(voice_type, source_unit)
		"graduate":
			play_graduate_voice(voice_type, source_unit)
		"professor":
			play_professor_voice(voice_type, source_unit)
		"armi":
			play_armi_voice(voice_type, source_unit)

func _get_unit_voice_kind(unit) -> String:
	if is_student_unit(unit):
		return "student"
	if is_graduate_unit(unit):
		return "graduate"
	if is_professor_unit(unit):
		return "professor"
	if is_armi_unit(unit):
		return "armi"
	return ""

func _process(_delta):
	_update_performance_cache(_delta)
	_process_upgrades(_delta)
	if current_command == CommandMode.ATTACK and not Input.is_key_pressed(KEY_A) and not attack_button_latched:
		current_command = CommandMode.NONE
		_refresh_command_ui()

func _update_performance_cache(delta: float):
	performance_cache_timer -= delta
	if performance_cache_timer > 0.0:
		return
	performance_cache_timer = 0.35
	cached_units = get_tree().get_nodes_in_group("Unit")
	cached_enemies = get_tree().get_nodes_in_group("Enemy")
	cached_obstacles = get_tree().get_nodes_in_group("Building") + get_tree().get_nodes_in_group("ResourceDeposit") + get_tree().get_nodes_in_group("Ruins")
	cached_ally_targets = []
	cached_enemy_targets = []
	for unit in cached_units:
		if not is_instance_valid(unit) or not (unit is Node2D) or not ("hp" in unit) or unit.hp <= 0:
			continue
		if unit.is_in_group("Enemy"):
			cached_enemy_targets.append(unit)
		elif unit.is_in_group("Ally"):
			cached_ally_targets.append(unit)
	for building in get_tree().get_nodes_in_group("Building"):
		if not is_instance_valid(building) or not (building is Node2D) or not ("hp" in building) or building.hp <= 0:
			continue
		if building.is_in_group("Enemy"):
			cached_enemy_targets.append(building)
		elif building.is_in_group("Ally"):
			cached_ally_targets.append(building)

func get_cached_units() -> Array:
	return cached_units

func get_cached_enemies() -> Array:
	return cached_enemies

func get_cached_obstacles() -> Array:
	return cached_obstacles

func get_cached_ally_targets() -> Array:
	return cached_ally_targets

func get_cached_enemy_targets() -> Array:
	return cached_enemy_targets

# --- 유닛 선택 로직 ---
func check_unit():
	if is_double_clicking:
		is_double_clicking = false 
		return 
		
	for u in unit_selected:
		if is_instance_valid(u):
			u.deselect()
	unit_selected = []
	
	for unit in get_tree().get_nodes_in_group("Unit"):
		if selected_rect.intersects(unit.get_rect()):
			unit.select()
			unit_selected.append(unit)
	_play_dominant_selected_voice("what")
	
	# 드래그로 유닛을 새로 할당했을 때 즉시 UI 불빛 동기화
	_refresh_command_ui()

# ----- 마우스 및 키보드 입력 처리 로직 -----
func _unhandled_input(event):
	# ★ [안전망 추가] 현재 씬이 null 상태(씬 전환 중)라면 입력을 무시하고 리턴합니다.
	if get_tree().current_scene == null: return
	if event.is_action_pressed("ui_cancel") or (event is InputEventKey and event.is_pressed() and not event.is_echo() and event.keycode == KEY_ESCAPE):
		if _handle_escape_for_selection():
			get_viewport().set_input_as_handled()
			return
	
	if get_viewport().gui_get_hovered_control() != null: return
		
	# 이제 current_scene이 확실히 있을 때만 find_child를 호출하므로 절대 터지지 않습니다.
	var info_panel = get_tree().current_scene.find_child("InfoPanel", true, false)
	if info_panel and info_panel is Control and info_panel.is_visible_in_tree():
		var panel_rect = info_panel.get_global_rect()
		if panel_rect.has_point(get_viewport().get_mouse_position()): return

	var lab_pending_building = _get_selected_lab_pending_building()
	if lab_pending_building:
		if event.is_action_pressed("left_click"):
			lab_pending_building.confirm_laboratory_placement()
			get_viewport().set_input_as_handled()
			_refresh_command_ui()
			return
		if event.is_action_pressed("right_click"):
			lab_pending_building.cancel_laboratory_placement()
			get_viewport().set_input_as_handled()
			_refresh_command_ui()
			return

	# ----- 이하 기존 코드와 동일 -----

	# ----- [키보드] A 단축키 누르기 / 떼기 실시간 감지 -----
	if event is InputEventKey and event.keycode == KEY_A:
		var valid_allies = unit_selected.filter(func(u): return is_instance_valid(u) and u.is_in_group("Ally"))
		if not valid_allies.is_empty():
			if event.is_pressed() and not event.is_echo():
				attack_button_latched = false
				current_command = CommandMode.ATTACK
			elif event.is_released():
				current_command = CommandMode.NONE
		elif event.is_released():
			current_command = CommandMode.NONE

	# ----- [마우스 우클릭] 기본 이동 및 공격이동/좌표할당 확정 -----
	if event.is_action_pressed("right_click"):
		var mouse_pos = get_global_mouse_position()
		var selected_buildings = _get_selected_rally_buildings()
		if not selected_buildings.is_empty() and not Input.is_key_pressed(KEY_A):
			var rally_resource = _get_resource_at_position(mouse_pos)
			for selected_building in selected_buildings:
				if rally_resource and selected_building.has_method("set_rally_resource"):
					selected_building.set_rally_resource(rally_resource)
				elif selected_building.has_method("set_rally_point"):
					selected_building.set_rally_point(mouse_pos)
			current_command = CommandMode.NONE
			get_viewport().set_input_as_handled()
			return

		var valid_allies = unit_selected.filter(func(u): return is_instance_valid(u) and u.is_in_group("Ally"))
		if valid_allies.size() == 0:
			current_command = CommandMode.NONE
			return

		if Input.is_key_pressed(KEY_A) or current_command == CommandMode.ATTACK:
			_issue_attack_order_at(mouse_pos)
			if not Input.is_key_pressed(KEY_A):
				attack_button_latched = false
				current_command = CommandMode.NONE
			get_viewport().set_input_as_handled()
			return

		# 이동 버튼(좌클릭)을 눌러서 '이동 조준 모드'일 때 우클릭을 하면 그 자리에 이동시키고 모드 해제 (불 꺼짐)
		if current_command == CommandMode.MOVE:
			move_to_position(mouse_pos)
			current_command = CommandMode.NONE
			get_viewport().set_input_as_handled()
			return

		# 아무 모드도 아닐 때 우클릭은 정석 우클릭 강제공격 및 일반 이동
		elif current_command == CommandMode.GATHER:
			var resource_target = _get_resource_at_position(mouse_pos)
			if resource_target:
				gather_from_resource(resource_target)
			current_command = CommandMode.NONE
			get_viewport().set_input_as_handled()
			return

		var clicked_resource = _get_resource_at_position(mouse_pos)
		if clicked_resource:
			gather_from_resource(clicked_resource)
			current_command = CommandMode.NONE
			return

		var clicked_target = _get_attack_target_at_position(mouse_pos)
		if clicked_target:
			if clicked_target.is_in_group("Ally") and clicked_target.is_in_group("Building") and "is_under_construction" in clicked_target and clicked_target.is_under_construction:
				resume_building(clicked_target)
			else:
				move_to_position(clicked_target.global_position)
			current_command = CommandMode.NONE
			return

		move_to_position(mouse_pos)

	# ----- [마우스 좌클릭] 오직 할당 및 명령 확정에만 사용 -----
	elif event.is_action_pressed("left_click"):
		var mouse_pos = get_global_mouse_position()

		if Input.is_key_pressed(KEY_A) or current_command == CommandMode.ATTACK:
			var valid_allies = unit_selected.filter(func(u): return is_instance_valid(u) and u.is_in_group("Ally"))
			if not valid_allies.is_empty():
				_issue_attack_order_at(mouse_pos)
				if not Input.is_key_pressed(KEY_A):
					attack_button_latched = false
					current_command = CommandMode.NONE
				get_viewport().set_input_as_handled()
				return
		
		if current_command == CommandMode.GATHER:
			var resource_target = _get_resource_at_position(mouse_pos)
			if resource_target:
				gather_from_resource(resource_target)
			current_command = CommandMode.NONE
			get_viewport().set_input_as_handled()
			return
			
		# 이동 버튼을 누른 상태에서 좌클릭으로 땅을 찍으면 이동 명령 확정 (모드 해제)
		elif current_command == CommandMode.MOVE:
			move_to_position(mouse_pos)
			current_command = CommandMode.NONE
			get_viewport().set_input_as_handled()
			return
			
		elif current_command == CommandMode.NONE:
			var clicked_unit = _get_unit_at_position(mouse_pos)
			if clicked_unit:
				var current_time = Time.get_ticks_msec() / 1000.0
				if clicked_unit == last_clicked_unit and (current_time - last_click_time) <= DOUBLE_CLICK_DELAY:
					is_double_clicking = true 
					_select_all_same_units_in_screen(clicked_unit)
					last_click_time = 0.0
					last_clicked_unit = null
				else:
					if unit_selected.has(clicked_unit) and unit_selected.size() > 1:
						pass 
					else:
						_select_single_unit(clicked_unit)
					last_click_time = current_time
					last_clicked_unit = clicked_unit
				get_viewport().set_input_as_handled()
			else:
				var clicked_resource = _get_resource_at_position(mouse_pos)
				if clicked_resource:
					_select_single_object(clicked_resource)
					get_viewport().set_input_as_handled()
				else:
					var clicked_ruins = _get_ruins_at_position(mouse_pos)
					if clicked_ruins:
						_select_single_object(clicked_ruins)
						get_viewport().set_input_as_handled()
					else:
						var clicked_building = _get_building_at_position(mouse_pos)
						if clicked_building:
							if _is_shift_pressed() and _has_selected_building():
								_add_object_to_selection(clicked_building)
								last_click_time = 0.0
								last_clicked_unit = null
								get_viewport().set_input_as_handled()
								return
							var current_time = Time.get_ticks_msec() / 1000.0
							if clicked_building == last_clicked_unit and (current_time - last_click_time) <= DOUBLE_CLICK_DELAY:
								is_double_clicking = true
								_select_all_same_buildings_in_screen(clicked_building)
								last_click_time = 0.0
								last_clicked_unit = null
							else:
								if unit_selected.has(clicked_building) and unit_selected.size() > 1:
									pass
								else:
									_select_single_object(clicked_building)
								last_click_time = current_time
								last_clicked_unit = clicked_building
							get_viewport().set_input_as_handled()
						else:
							_clear_selection()

# ★ [구조 변경 핵심] 유닛의 실시간 이동 상태를 파악하여 UI 창에 불빛 상태만 전달하는 전용 함수
func _refresh_command_ui():
	var valid_allies = unit_selected.filter(func(u): return is_instance_valid(u) and u.is_in_group("Ally"))
	
	if get_tree().current_scene == null:
		return
	var info_panel = get_tree().current_scene.find_child("InfoPanel", true, false)
	if info_panel and info_panel.has_method("display_units"):
		info_panel.display_units(unit_selected)
		
	var command_center = get_tree().get_first_node_in_group("CommandCenter")
	if command_center and command_center.has_method("update_command_window"):
		# 명령 센터(또는 UI창)에 유닛 목록을 보낼 때, 현재 매니저의 입력 모드 상태를 기반으로 업데이트합니다.
		command_center.update_command_window(unit_selected)
		
		# 만약 커맨드 센터에서 버튼들의 하이라이트(불빛)를 직접 제어하고 있다면,
		# 아래 로직을 통해 유닛들의 실제 이동 상태를 수동으로 동기화해 줍니다.
		var is_moving = false
		var is_attack_moving = false
		
		for ally in valid_allies:
			if "current_state" in ally:
				if ally.current_state == 1:   # State.MOVING
					is_moving = true
				elif ally.current_state == 2: # State.ATTACK_MOVE
					is_attack_moving = true
		
		# 커맨드센터의 불빛 갱신 로직이 current_command 변수에 의존한다면 
		# 버튼을 강제로 활성화 상태로 보여주기 위해 임시로 판단 기준을 제공합니다.
		if current_command == CommandMode.NONE:
			if is_moving and command_center.has_method("highlight_move_button"):
				command_center.highlight_move_button(true)
			if is_attack_moving and command_center.has_method("highlight_attack_button"):
				command_center.highlight_attack_button(true)

# 유닛이 멈췄을 때 유닛 스크립트에서 호출해 주는 바인딩 함수
func _refresh_command_mode_by_selection():
	_refresh_command_ui()

func _handle_escape_for_selection() -> bool:
	var placement = get_tree().get_first_node_in_group("BuildingPlacement")
	if placement and "active" in placement and placement.active:
		if placement.has_method("cancel"):
			placement.cancel()
		current_command = CommandMode.NONE
		_refresh_command_ui()
		return true
	var lab_pending_building = _get_selected_lab_pending_building()
	if lab_pending_building:
		lab_pending_building.cancel_laboratory_placement()
		current_command = CommandMode.NONE
		_refresh_command_ui()
		return true
	if unit_selected.is_empty():
		return false
	if _return_selected_menu_to_previous_step():
		current_command = CommandMode.NONE
		_refresh_command_ui()
		return true
	current_command = CommandMode.NONE
	_clear_selection()
	return true

func _return_selected_menu_to_previous_step() -> bool:
	var changed := false
	for selected in unit_selected:
		if not is_instance_valid(selected):
			continue
		if "current_menu_page" in selected and selected.current_menu_page != "base":
			selected.current_menu_page = "base"
			changed = true
	return changed

func _get_unit_at_position(pos: Vector2):
	for unit in get_tree().get_nodes_in_group("Unit"):
		if is_instance_valid(unit) and unit.get_rect().has_point(pos):
			return unit
	return null

func _get_resource_at_position(pos: Vector2):
	for resource in get_tree().get_nodes_in_group("ResourceDeposit"):
		if is_instance_valid(resource):
			if resource.has_method("get_rect") and resource.get_rect().has_point(pos):
				return resource
			elif resource is Node2D and resource.global_position.distance_to(pos) <= 32.0:
				return resource
	return null

func _get_ruins_at_position(pos: Vector2):
	for ruins in get_tree().get_nodes_in_group("Ruins"):
		if is_instance_valid(ruins) and ruins.visible:
			if ruins.has_method("get_rect") and ruins.get_rect().has_point(pos):
				return ruins
			elif ruins is Node2D and ruins.global_position.distance_to(pos) <= 48.0:
				return ruins
	return null

func _get_building_at_position(pos: Vector2):
	for building in get_tree().get_nodes_in_group("Building"):
		if is_instance_valid(building):
			if building.has_method("get_rect") and building.get_rect().has_point(pos):
				return building
			elif building is Node2D and building.global_position.distance_to(pos) <= 48.0:
				return building
	for dropoff in get_tree().get_nodes_in_group("ResourceDropoff"):
		if is_instance_valid(dropoff) and not dropoff.is_in_group("ResourceDeposit"):
			if dropoff.has_method("get_rect") and dropoff.get_rect().has_point(pos):
				return dropoff
			elif dropoff is Node2D and dropoff.global_position.distance_to(pos) <= 48.0:
				return dropoff
	return null

func _get_attack_target_at_position(pos: Vector2):
	var unit = _get_unit_at_position(pos)
	if unit:
		return unit
	return _get_building_at_position(pos)

func _get_selected_rally_buildings() -> Array:
	var buildings: Array = []
	if unit_selected.is_empty():
		return buildings
	for selected in unit_selected:
		if not is_instance_valid(selected) or not selected.is_in_group("Building") or not selected.has_method("set_rally_point"):
			return []
		if selected.has_method("can_set_rally_point") and not selected.can_set_rally_point():
			return []
		buildings.append(selected)
	if not _are_buildings_same_type(buildings):
		return []
	return buildings

func _get_selected_rally_building():
	var buildings = _get_selected_rally_buildings()
	return buildings[0] if buildings.size() == 1 else null

func _get_selected_lab_pending_building():
	if unit_selected.size() != 1:
		return null
	var selected = unit_selected[0]
	if is_instance_valid(selected) and selected.has_method("is_waiting_for_laboratory_placement") and selected.is_waiting_for_laboratory_placement():
		return selected
	return null

func _select_single_unit(target_unit: Node):
	play_mouse_click_sound()
	_clear_destination_markers()
	for u in unit_selected:
		if is_instance_valid(u):
			u.deselect()
	unit_selected = []
	
	target_unit.select()
	unit_selected.append(target_unit)
	_play_dominant_selected_voice("what")
	_refresh_command_ui()

func _select_single_object(target_object: Node):
	play_mouse_click_sound()
	_clear_destination_markers()
	for u in unit_selected:
		if is_instance_valid(u) and u.has_method("deselect"):
			u.deselect()
	unit_selected = []
	
	if target_object.has_method("select"):
		target_object.select()
	unit_selected.append(target_object)
	current_command = CommandMode.NONE
	_refresh_command_ui()

func _add_object_to_selection(target_object: Node):
	if not is_instance_valid(target_object) or not target_object.is_in_group("Building"):
		return
	for selected in unit_selected:
		if not is_instance_valid(selected) or not selected.is_in_group("Building"):
			return
	if unit_selected.has(target_object):
		return
	play_mouse_click_sound()
	if target_object.has_method("select"):
		target_object.select()
	unit_selected.append(target_object)
	current_command = CommandMode.NONE
	_refresh_command_ui()

func _select_all_same_units_in_screen(base_unit: Node):
	play_mouse_click_sound()
	_clear_destination_markers()
	for u in unit_selected:
		if is_instance_valid(u):
			u.deselect()
	unit_selected = []
	
	var viewport_rect = get_viewport().get_visible_rect()
	var camera = get_viewport().get_camera_2d()
	var screen_rect: Rect2
	if camera:
		screen_rect = Rect2(camera.get_screen_center_position() - viewport_rect.size / 2.0, viewport_rect.size)
	else:
		screen_rect = viewport_rect

	var base_clean_name = base_unit.unit_name.strip_edges() if "unit_name" in base_unit else ""

	for unit in get_tree().get_nodes_in_group("Unit"):
		if is_instance_valid(unit) and "unit_name" in unit:
			var unit_clean_name = unit.unit_name.strip_edges()
			var is_same_type = (unit_clean_name == base_clean_name)
			var is_in_screen = screen_rect.has_point(unit.global_position)
			
			if is_same_type and is_in_screen:
				unit.select()
				unit_selected.append(unit)
				
	_play_dominant_selected_voice("what")
	_refresh_command_ui()

func _select_all_same_buildings_in_screen(base_building: Node):
	play_mouse_click_sound()
	_clear_destination_markers()
	for u in unit_selected:
		if is_instance_valid(u) and u.has_method("deselect"):
			u.deselect()
	unit_selected = []
	var screen_rect = _get_camera_world_rect()
	var base_name = str(base_building.building_name if "building_name" in base_building else base_building.name).strip_edges()
	for building in get_tree().get_nodes_in_group("Building"):
		if not is_instance_valid(building) or not ("building_name" in building):
			continue
		var building_name = str(building.building_name).strip_edges()
		if building_name == base_name and screen_rect.has_point(building.global_position):
			if building.has_method("select"):
				building.select()
			unit_selected.append(building)
	_refresh_command_ui()

func _get_camera_world_rect() -> Rect2:
	var viewport_rect = get_viewport().get_visible_rect()
	var camera = get_viewport().get_camera_2d()
	if camera:
		var world_size = viewport_rect.size * camera.zoom
		return Rect2(camera.get_screen_center_position() - world_size / 2.0, world_size)
	return viewport_rect

func _is_node_in_camera_view(node: Node, margin: float = 48.0) -> bool:
	if not is_instance_valid(node) or not node is Node2D:
		return false
	return _get_camera_world_rect().grow(margin).has_point(node.global_position)

func _clear_selection():
	_clear_destination_markers()
	for u in unit_selected:
		if is_instance_valid(u):
			if "current_menu_page" in u:
				u.current_menu_page = "base"
			if u.has_method("deselect"):
				u.deselect()
	unit_selected = []
	current_command = CommandMode.NONE
	_refresh_command_ui()

func move_to_position(target_pos: Vector2):
	var valid_allies = unit_selected.filter(func(u): return is_instance_valid(u) and u.is_in_group("Ally"))
	if valid_allies.size() == 0: return
	play_mouse_click_sound()
	_play_dominant_selected_voice("move")
	_show_destination_marker(target_pos, false)

	var points = _generate_circular_formation(target_pos, valid_allies.size(), spacing)
	var append_order = _is_shift_pressed()
	for i in range(valid_allies.size()):
		if valid_allies[i].has_method("set_target"):
			valid_allies[i].set_target(points[i], append_order)

func attack_move_to_position(target_pos: Vector2):
	var valid_allies = unit_selected.filter(func(u): return is_instance_valid(u) and u.is_in_group("Ally"))
	if valid_allies.size() == 0: return
	play_mouse_click_sound()
	_play_dominant_selected_voice("yes")
	_show_destination_marker(target_pos, true)

	var points = _generate_circular_formation(target_pos, valid_allies.size(), spacing)
	var append_order = _is_shift_pressed()
	for i in range(valid_allies.size()):
		if valid_allies[i].has_method("set_attack_move"):
			valid_allies[i].set_attack_move(points[i], append_order)

func _issue_attack_order_at(mouse_pos: Vector2):
	var valid_allies = unit_selected.filter(func(u): return is_instance_valid(u) and u.is_in_group("Ally"))
	if valid_allies.is_empty():
		current_command = CommandMode.NONE
		return
	var attack_target = _get_attack_target_at_position(mouse_pos)
	if attack_target:
		play_mouse_click_sound()
		_play_dominant_selected_voice("yes")
		for ally in valid_allies:
			if ally != attack_target and ally.has_method("force_attack_target"):
				ally.force_attack_target(attack_target)
		if attack_target is Node2D:
			_show_destination_marker(attack_target.global_position, true)
	else:
		attack_move_to_position(mouse_pos)
	current_command = CommandMode.ATTACK

func gather_from_resource(resource: Node2D):
	var gatherers = unit_selected.filter(func(u): return is_instance_valid(u) and u.is_in_group("Ally") and u.has_method("start_gathering"))
	if gatherers.size() == 0 or not is_instance_valid(resource):
		return
	play_mouse_click_sound()
	_play_dominant_selected_voice("yes")
	var dropoff = _find_nearest_dropoff(resource.global_position)
	var append_order = _is_shift_pressed()
	for gatherer in gatherers:
		gatherer.start_gathering(resource, dropoff, append_order)

func resume_building(building: Node2D):
	if not is_instance_valid(building):
		return
	var builders = unit_selected.filter(func(u): return is_instance_valid(u) and u.is_in_group("Ally") and u.has_method("resume_building_site") and "can_build" in u and u.can_build)
	if builders.is_empty():
		return
	play_mouse_click_sound()
	_play_dominant_selected_voice("yes")
	var append_order = _is_shift_pressed()
	for builder in builders:
		builder.resume_building_site(building, append_order)

func _show_destination_marker(target_pos: Vector2, is_attack: bool):
	if is_attack:
		_clear_marker(move_destination_marker)
		move_destination_marker = null
		attack_destination_marker = _create_or_update_marker(attack_destination_marker, ATTACK_DESTINATION_TEXTURE, target_pos)
	else:
		_clear_marker(attack_destination_marker)
		attack_destination_marker = null
		move_destination_marker = _create_or_update_marker(move_destination_marker, MOVE_DESTINATION_TEXTURE, target_pos)

func _create_or_update_marker(marker: Sprite2D, texture: Texture2D, target_pos: Vector2) -> Sprite2D:
	if not is_instance_valid(marker):
		marker = Sprite2D.new()
		marker.name = "CommandDestinationMarker"
		marker.centered = true
		marker.z_as_relative = false
		marker.z_index = 4090
		add_child(marker)
	marker.texture = texture
	marker.global_position = target_pos
	marker.visible = true
	return marker

func _clear_marker(marker: Sprite2D):
	if is_instance_valid(marker):
		marker.queue_free()

func _clear_destination_markers():
	_clear_marker(move_destination_marker)
	_clear_marker(attack_destination_marker)
	move_destination_marker = null
	attack_destination_marker = null

func _get_available_builder(builders: Array):
	for builder in builders:
		if not ("current_state" in builder) or builder.current_state == 0:
			return builder
	for builder in builders:
		if not ("current_state" in builder) or (builder.current_state != 7 and builder.current_state != 8):
			return builder
	return builders[0]

func _is_shift_pressed() -> bool:
	return Input.is_key_pressed(KEY_SHIFT)

func _on_move_pressed():
	attack_button_latched = false
	current_command = CommandMode.MOVE
	_refresh_command_ui()

func _on_stop_pressed():
	attack_button_latched = false
	current_command = CommandMode.NONE
	var valid_allies = unit_selected.filter(func(u): return is_instance_valid(u) and u.is_in_group("Ally"))
	_play_dominant_selected_voice("yes")
	for ally in valid_allies:
		if ally.has_method("stop_order"):
			ally.stop_order()
		elif ally.has_method("_stop_unit"):
			ally._stop_unit()
	_refresh_command_ui()

func _on_attack_pressed():
	attack_button_latched = true
	current_command = CommandMode.ATTACK
	_refresh_command_ui()

func _on_gathering_pressed():
	attack_button_latched = false
	current_command = CommandMode.GATHER
	_refresh_command_ui()

func _on_train_unit_pressed():
	_issue_building_button_command("_on_train_unit_pressed")

func _on_train_professor_pressed():
	_issue_building_button_command("_on_train_professor_pressed")

func _on_train_armi_pressed():
	_issue_building_button_command("_on_train_armi_pressed")

func _on_build_lab_pressed():
	_issue_building_button_command("_on_build_lab_pressed")

func _on_upgrade_body_pressed():
	_issue_building_button_command("_on_upgrade_body_pressed")

func _on_upgrade_power_pressed():
	_issue_building_button_command("_on_upgrade_power_pressed")

func _on_upgrade_student_trait_pressed():
	_issue_building_button_command("_on_upgrade_student_trait_pressed")

func _on_upgrade_m_student_trait_pressed():
	_issue_building_button_command("_on_upgrade_m_student_trait_pressed")

func _on_upgrade_professor_trait_pressed():
	_issue_building_button_command("_on_upgrade_professor_trait_pressed")

func _on_upgrade_armi_trait_pressed():
	_issue_building_button_command("_on_upgrade_armi_trait_pressed")

func _issue_building_button_command(function_name: String):
	attack_button_latched = false
	current_command = CommandMode.NONE
	var building = _get_best_building_for_command(function_name)
	if building and building.has_method(function_name):
		building.call(function_name)
	else:
		_show_button_command_failures(function_name)
	_refresh_command_ui()

func issue_building_button_command_for_ids(function_name: String, building_ids: Array):
	attack_button_latched = false
	current_command = CommandMode.NONE
	var building = _get_best_building_for_command_from_ids(function_name, building_ids)
	if not building and _is_production_command(function_name):
		building = _get_first_building_for_command_from_ids(function_name, building_ids)
	if building and building.has_method(function_name):
		building.call(function_name)
	else:
		_show_button_command_failures(function_name)
	_refresh_command_ui()

func issue_selection_button_command_for_ids(function_name: String, selected_ids: Array):
	if _is_building_command(function_name):
		issue_building_button_command_for_ids(function_name, selected_ids)
		return
	if _is_builder_command(function_name) or _is_unit_action_command(function_name):
		attack_button_latched = false
		current_command = CommandMode.NONE
		unit_selected = _resolve_selection_ids(selected_ids)
		if has_method(function_name):
			call(function_name)
		_refresh_command_ui()
		return
	if has_method(function_name):
		call(function_name)

func _resolve_selection_ids(selected_ids: Array) -> Array:
	var resolved: Array = []
	for selected_id in selected_ids:
		var selected = instance_from_id(int(selected_id))
		if is_instance_valid(selected):
			resolved.append(selected)
	return resolved

func _get_best_building_for_command(function_name: String):
	if not _selection_allows_building_command_lookup():
		return null
	var selected_ids := []
	for selected in unit_selected:
		if is_instance_valid(selected):
			selected_ids.append(selected.get_instance_id())
	return _get_best_building_for_command_from_ids(function_name, selected_ids)

func _get_best_building_for_command_from_ids(function_name: String, building_ids: Array):
	var best = null
	var best_queue_size := 999999
	for building_id in building_ids:
		var selected = instance_from_id(int(building_id))
		if not is_instance_valid(selected) or not selected.is_in_group("Building") or not selected.has_method(function_name):
			continue
		if selected.has_method("can_accept_button_command") and not selected.can_accept_button_command(function_name):
			continue
		var queue_size = 0
		if selected.has_method("get_unit_production_queue_size"):
			queue_size = selected.get_unit_production_queue_size()
		elif selected.has_method("get_production_queue_size"):
			queue_size = selected.get_production_queue_size()
		if best == null or queue_size < best_queue_size:
			best = selected
			best_queue_size = queue_size
	return best

func _get_first_building_for_command_from_ids(function_name: String, building_ids: Array):
	for building_id in building_ids:
		var selected = instance_from_id(int(building_id))
		if is_instance_valid(selected) and selected.is_in_group("Building") and selected.has_method(function_name):
			return selected
	return null

func _show_button_command_failures(function_name: String):
	var upgrade_id := _get_upgrade_id_for_command(function_name)
	if not upgrade_id.is_empty() and is_upgrade_in_progress(upgrade_id):
		_show_hud_notice("진행중인 업그레이드입니다")
		return
	var shown := {}
	for selected in unit_selected:
		if not is_instance_valid(selected) or not selected.is_in_group("Building"):
			continue
		if not selected.has_method("get_button_command_block_message"):
			continue
		var message := str(selected.get_button_command_block_message(function_name))
		if message.is_empty() or shown.has(message):
			continue
		shown[message] = true
		_show_hud_notice(message)

func _get_upgrade_id_for_command(function_name: String) -> String:
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

func start_upgrade(upgrade_id: String) -> bool:
	return start_upgrade_for_building(upgrade_id, 0)

func start_upgrade_for_building(upgrade_id: String, building_id: int = 0) -> bool:
	if not can_start_upgrade_for_building(upgrade_id, building_id):
		if upgrades_in_progress.has(upgrade_id):
			_show_hud_notice("진행중인 업그레이드입니다")
		return false
	if not upgrade_levels.has(upgrade_id):
		return false
	var cost := get_upgrade_cost(upgrade_id)
	var hud: Node = _get_hud()
	if hud:
		if hud.has_method("get_cost_failure_message"):
			var cost_message: String = hud.get_cost_failure_message(cost.x, cost.y)
			if not cost_message.is_empty():
				hud.show_notice(cost_message)
				return false
		if hud.has_method("spend_resource") and not hud.spend_resource(cost.x, cost.y):
			return false
	upgrades_in_progress[upgrade_id] = {
		"time": UPGRADE_TIME,
		"building_id": building_id
	}
	_refresh_command_ui()
	return true

func _process_upgrades(delta: float):
	if upgrades_in_progress.is_empty():
		return
	var completed: Array[String] = []
	for upgrade_id in upgrades_in_progress.keys():
		var progress_data: Variant = upgrades_in_progress[upgrade_id]
		var remaining_time: float = 0.0
		if progress_data is Dictionary:
			remaining_time = float(progress_data.get("time", 0.0)) - delta
			progress_data["time"] = remaining_time
			upgrades_in_progress[upgrade_id] = progress_data
		else:
			remaining_time = float(progress_data) - delta
			upgrades_in_progress[upgrade_id] = remaining_time
		if remaining_time <= 0.0:
			completed.append(str(upgrade_id))
	for upgrade_id in completed:
		upgrades_in_progress.erase(upgrade_id)
		upgrade_levels[upgrade_id] = int(upgrade_levels.get(upgrade_id, 0)) + 1
		_apply_upgrades_to_all_units()
		play_ui_alert("upgrade_complete")
		_show_hud_notice("%s 강화가 완료되었습니다" % get_upgrade_display_name(upgrade_id))
	_refresh_command_ui()

func _apply_upgrades_to_all_units():
	for unit in get_tree().get_nodes_in_group("Unit"):
		if is_instance_valid(unit) and unit.is_in_group("Ally") and unit.has_method("apply_global_upgrades"):
			unit.apply_global_upgrades()

func get_upgrade_level(upgrade_id: String) -> int:
	return int(upgrade_levels.get(upgrade_id, 0))

func is_upgrade_in_progress(upgrade_id: String) -> bool:
	return upgrades_in_progress.has(upgrade_id)

func get_upgrade_progress(upgrade_id: String) -> float:
	if not upgrades_in_progress.has(upgrade_id):
		return 0.0
	var progress_data: Variant = upgrades_in_progress[upgrade_id]
	var remaining_time: float = float(progress_data.get("time", 0.0)) if progress_data is Dictionary else float(progress_data)
	return clamp(1.0 - (remaining_time / max(UPGRADE_TIME, 0.01)), 0.0, 1.0)

func get_upgrade_building_id(upgrade_id: String) -> int:
	if not upgrades_in_progress.has(upgrade_id):
		return 0
	var progress_data: Variant = upgrades_in_progress[upgrade_id]
	if progress_data is Dictionary:
		return int(progress_data.get("building_id", 0))
	return 0

func can_start_upgrade(upgrade_id: String) -> bool:
	return upgrade_levels.has(upgrade_id) and not is_upgrade_in_progress(upgrade_id) and get_upgrade_level(upgrade_id) < _get_upgrade_max_level(upgrade_id)

func can_start_upgrade_for_building(upgrade_id: String, _building_id: int = 0) -> bool:
	if not upgrade_levels.has(upgrade_id):
		return false
	if is_upgrade_in_progress(upgrade_id):
		return false
	if get_upgrade_level(upgrade_id) >= _get_upgrade_max_level(upgrade_id):
		return false
	return true

func _is_building_running_upgrade(building_id: int) -> bool:
	if building_id == 0:
		return false
	for upgrade_id in upgrades_in_progress.keys():
		var progress_data: Variant = upgrades_in_progress[upgrade_id]
		if progress_data is Dictionary and int(progress_data.get("building_id", 0)) == building_id:
			return true
	return false

func get_upgrade_icon_path(upgrade_id: String) -> String:
	var level := get_upgrade_level(upgrade_id)
	if upgrade_id == "body" or upgrade_id == "power":
		level = mini(level + 1, 3)
		return "res://icon/%s%d_upgrd.png" % [upgrade_id, level]
	level = mini(level + 1, 1)
	return "res://icon/%s%d_upgrd.png" % [upgrade_id, level]

func get_completed_upgrade_icon_path(upgrade_id: String) -> String:
	var level := get_upgrade_level(upgrade_id)
	return "res://icon/%s%d_upgrd.png" % [upgrade_id, level]

func get_upgrade_tooltip(upgrade_id: String) -> String:
	var cost := get_upgrade_cost(upgrade_id)
	return _get_upgrade_button_tooltip(upgrade_id, cost)

func _get_upgrade_button_tooltip(upgrade_id: String, cost: Vector2i) -> String:
	var mineral_color := _get_cost_color(cost.x, 0)
	var gas_color := _get_cost_color(0, cost.y)
	var cost_line := "비용: [color=%s]%d[/color]/[color=%s]%d[/color]" % [mineral_color, cost.x, gas_color, cost.y]
	var time_line := "시간: [color=#56a8ff]%d초[/color]" % int(UPGRADE_TIME)
	var level := get_upgrade_level(upgrade_id)
	match upgrade_id:
		"body":
			var body_next_level = mini(level + 1, 3)
			var body_title := _get_body_upgrade_title(body_next_level)
			return "[color=#ff9f33]%s[/color]\n[color=#56a8ff]체력배수: %.1f->%.1f[/color]\n%s\n%s" % [body_title, _get_level_multiplier(level), _get_level_multiplier(body_next_level), cost_line, time_line]
		"power":
			var power_next_level = mini(level + 1, 3)
			var power_title := _get_power_upgrade_title(power_next_level)
			return "[color=#ff9f33]%s[/color]\n[color=#56a8ff]공격배수: %.1f->%.1f[/color]\n%s\n%s" % [power_title, _get_level_multiplier(level), _get_level_multiplier(power_next_level), cost_line, time_line]
		"student":
			return "[color=#ff9f33]등록금 인상[/color]\n[color=#56a8ff]학생[/color] 특성 강화\n[color=#56a8ff]채취량: 50->100[/color]\n%s\n%s" % [cost_line, time_line]
		"m_student":
			return "[color=#ff9f33]인간시대의 끝[/color]\n[color=#56a8ff]대학원생[/color] 특성 강화\n[color=#56a8ff]채취량: 50->100[/color]\n%s\n%s" % [cost_line, time_line]
		"professor":
			return "[color=#ff9f33]교수님의 과제[/color]\n[color=#56a8ff]교수[/color] 특성 강화\n[color=#56a8ff]마나량배수: 1.0>1.5[/color]\n[color=#56a8ff]회복량: 1->3[/color]\n%s\n%s" % [cost_line, time_line]
		"armi":
			return "[color=#ff9f33]진짜 사나이[/color]\n[color=#56a8ff]예비군[/color] 특성 강화\n[color=#56a8ff]이동속도배수: 1.0->1.5[/color]\n%s\n%s" % [cost_line, time_line]
	return ""

func _get_cost_color(mineral_cost: int, gas_cost: int) -> String:
	var hud = _get_hud()
	if not hud or not hud.has_method("can_afford"):
		return "#56a8ff"
	return "#56a8ff" if hud.can_afford(mineral_cost, gas_cost) else "#ff4a4a"

func get_upgrade_cost(upgrade_id: String) -> Vector2i:
	if upgrade_id == "body" or upgrade_id == "power":
		match get_upgrade_level(upgrade_id) + 1:
			1:
				return Vector2i(150, 150)
			2:
				return Vector2i(250, 250)
			3:
				return Vector2i(350, 350)
		return Vector2i.ZERO
	return Vector2i(150, 150)

func get_upgrade_display_name(upgrade_id: String) -> String:
	match upgrade_id:
		"body":
			return "체력 강화"
		"power":
			return "공격력 강화"
		"student":
			return "학생 특성 강화"
		"m_student":
			return "대학원생 특성 강화"
		"professor":
			return "교수 특성 강화"
		"armi":
			return "예비군 특성 강화"
	return "강화"

func get_upgrade_effect_text(upgrade_id: String, level: int = -1) -> String:
	if level < 0:
		level = get_upgrade_level(upgrade_id)
	match upgrade_id:
		"body":
			return "최대체력 %.1f배" % _get_level_multiplier(level)
		"power":
			return "공격력 %.1f배" % _get_level_multiplier(level)
		"student":
			return "채취량 2배" if level > 0 else "기본 채취량"
		"m_student":
			return "공격 쿨타임 0.5배" if level > 0 else "기본 쿨타임"
		"professor":
			return "마나 1.5배, 회복량 +2" if level > 0 else "기본 회복"
		"armi":
			return "이동속도 1.5배" if level > 0 else "기본 이동속도"
	return ""

func get_current_upgrade_tooltip(upgrade_id: String) -> String:
	var level := get_upgrade_level(upgrade_id)
	match upgrade_id:
		"body":
			return _get_body_current_tooltip(level)
		"power":
			return _get_power_current_tooltip(level)
		"student":
			return _get_student_current_tooltip(level)
		"m_student":
			return _get_graduate_current_tooltip(level)
		"professor":
			return _get_professor_current_tooltip(level)
		"armi":
			return _get_armi_current_tooltip(level)
	return ""

func _get_body_upgrade_title(level: int) -> String:
	match clampi(level, 0, 3):
		0:
			return "공부하다가 망가진 몸"
		1:
			return "건강한 몸"
		2:
			return "운동 애호가"
		3:
			return "초사이어인"
	return "체력 강화"

func _get_power_upgrade_title(level: int) -> String:
	match clampi(level, 0, 3):
		0:
			return "팬은 칼보다 강하다"
		1:
			return "이제 책을 곁드린"
		2:
			return "공부를 합시다"
		3:
			return "고성능 노트북"
	return "공격력 강화"

func _get_body_current_tooltip(level: int) -> String:
	match clampi(level, 0, 3):
		0:
			return "[color=#ff9f33]공부하다가 망가진 몸[/color]\n공부만하지 할고\n운동도 하세요\n[color=#ff9f33]체력 0강[/color]\n[color=#ff9f33]체력배수: 1.0배[/color]"
		1:
			return "[color=#ff9f33]건강한 몸[/color]\n안녕 난 척추의 요정\n스트레칭을 해보자\n[color=#ff9f33]체력 1강[/color]\n[color=#ff9f33]체력배수: 1.2배[/color]"
		2:
			return "[color=#ff9f33]운동 애호가[/color]\n어떤 유명인이 말했죠\n헬스클럽은 클럽보다 즐거운 곳\n[color=#ff9f33]체력 2강[/color]\n[color=#ff9f33]체력배수: 1.5배[/color]"
		3:
			return "[color=#ff9f33]초사이어인[/color]\n인간을 넘어선 무언가\n대학생 맞죠?\n[color=#ff9f33]체력 3강[/color]\n[color=#ff9f33]체력배수: 2.0배[/color]"
	return ""

func _get_power_current_tooltip(level: int) -> String:
	match clampi(level, 0, 3):
		0:
			return "[color=#ff9f33]팬은 칼보다 강하다[/color]\n팬으로 공부하는 사람이\n요즘은 없더라구요\n[color=#ff9f33]공격력 0강[/color]\n[color=#ff9f33]공격배수: 1.0배[/color]"
		1:
			return "[color=#ff9f33]이제 책을 곁드린[/color]\n종이책을 다들 \n안쓰더라고요\n[color=#ff9f33]공격력 1강[/color]\n[color=#ff9f33]공격배수: 1.2배[/color]"
		2:
			return "[color=#ff9f33]공부를 합시다[/color]\n다들 패드 쓰는데\n종이책 맛이 있습니다\n[color=#ff9f33]공격력 2강[/color]\n[color=#ff9f33]공격배수: 1.5배[/color]"
		3:
			return "[color=#ff9f33]고성능 노트북[/color]\n요즘 램값이 비싸더라요\n무려 170만원\n[color=#ff9f33]공격력 3강[/color]\n[color=#ff9f33]공격배수: 2.0배[/color]"
	return ""

func _get_student_current_tooltip(level: int) -> String:
	if level > 0:
		return "[color=#ff9f33]등록금 인상[/color]\n[color=#56a8ff]1회 채취량: 100[/color]"
	return "[color=#ff9f33]등록금 노예[/color]\n[color=#56a8ff]1회 채취량: 50[/color]"

func _get_graduate_current_tooltip(level: int) -> String:
	if level > 0:
		return "[color=#ff9f33]인간시대의 끝[/color]\n[color=#56a8ff]1회 최종 체력배수: 2.0[/color]"
	return "[color=#ff9f33]노력하는 두뇌[/color]\n[color=#56a8ff]1회 최종 체력배수: 1.0[/color]"

func _get_professor_current_tooltip(level: int) -> String:
	if level > 0:
		return "[color=#ff9f33]교수님의 과제[/color]\n[color=#56a8ff]마나량배수: 1.5[/color]\n[color=#56a8ff]회복량: 3[/color]"
	return "[color=#ff9f33]교수님의 지식[/color]\n[color=#56a8ff]마나량배수: 1.0[/color]\n[color=#56a8ff]회복량: 1[/color]"

func _get_armi_current_tooltip(level: int) -> String:
	if level > 0:
		return "[color=#ff9f33]진짜 사나이[/color]\n[color=#56a8ff]이동속도배수: 1.5[/color]"
	return "[color=#ff9f33]어서와 군대는 처음이지?[/color]\n[color=#56a8ff]이동속도배수: 1.0[/color]"

func get_unit_trait_upgrade_id(unit) -> String:
	var path := str(unit.scene_file_path if "scene_file_path" in unit else "")
	if path.ends_with("student.tscn"):
		return "student"
	if path.ends_with("graduate_student.tscn"):
		return "m_student"
	if path.ends_with("professor.tscn"):
		return "professor"
	if path.ends_with("armi.tscn"):
		return "armi"
	return ""

func get_unit_upgrade_icon_paths(unit) -> Array:
	var icons := [get_completed_upgrade_icon_path("body"), get_completed_upgrade_icon_path("power")]
	var trait_id := get_unit_trait_upgrade_id(unit)
	if not trait_id.is_empty():
		icons.append(get_completed_upgrade_icon_path(trait_id))
	return icons

func get_unit_upgrade_tooltips(unit) -> Array:
	var tips := [get_current_upgrade_tooltip("body"), get_current_upgrade_tooltip("power")]
	var trait_id := get_unit_trait_upgrade_id(unit)
	if not trait_id.is_empty():
		tips.append(get_current_upgrade_tooltip(trait_id))
	return tips

func get_unit_upgrade_summary(unit) -> String:
	var parts := [
		"체력 %d강" % get_upgrade_level("body"),
		"공격력 %d강" % get_upgrade_level("power")
	]
	var trait_id := get_unit_trait_upgrade_id(unit)
	if not trait_id.is_empty():
		parts.append("%s %d강" % [get_upgrade_display_name(trait_id), get_upgrade_level(trait_id)])
	return " / ".join(parts)

func get_body_multiplier() -> float:
	return _get_level_multiplier(get_upgrade_level("body"))

func get_power_multiplier() -> float:
	return _get_level_multiplier(get_upgrade_level("power"))

func _get_level_multiplier(level: int) -> float:
	match clampi(level, 0, 3):
		1:
			return 1.2
		2:
			return 1.5
		3:
			return 2.0
	return 1.0

func _get_upgrade_max_level(upgrade_id: String) -> int:
	return 3 if upgrade_id == "body" or upgrade_id == "power" else 1

func is_button_enabled_for_selection(function_name: String, default_disabled: bool) -> bool:
	if _is_building_command(function_name):
		if not _selection_allows_building_command_lookup():
			return false
	if not default_disabled:
		return true
	if _is_building_command(function_name):
		return _get_best_building_for_command(function_name) != null
	return false

func _is_building_command(function_name: String) -> bool:
	return [
		"_on_train_unit_pressed",
		"_on_train_professor_pressed",
		"_on_train_armi_pressed",
		"_on_build_lab_pressed",
		"_on_upgrade_body_pressed",
		"_on_upgrade_power_pressed",
		"_on_upgrade_student_trait_pressed",
		"_on_upgrade_m_student_trait_pressed",
		"_on_upgrade_professor_trait_pressed",
		"_on_upgrade_armi_trait_pressed"
	].has(function_name)

func _is_production_command(function_name: String) -> bool:
	return [
		"_on_train_unit_pressed",
		"_on_train_professor_pressed",
		"_on_train_armi_pressed"
	].has(function_name)

func _is_builder_command(function_name: String) -> bool:
	return [
		"_on_build_basic_pressed",
		"_on_build_supply_pressed",
		"_on_build_excavation_pressed",
		"_on_build_barracks_pressed",
		"_on_build_army_training_pressed"
	].has(function_name)

func _is_unit_action_command(function_name: String) -> bool:
	return [
		"_on_move_pressed",
		"_on_stop_pressed",
		"_on_attack_pressed",
		"_on_gathering_pressed"
	].has(function_name)

func is_snapshot_button_command(function_name: String) -> bool:
	return _is_building_command(function_name) or _is_builder_command(function_name) or _is_unit_action_command(function_name)

func is_building_button_command(function_name: String) -> bool:
	return _is_building_command(function_name)

func _has_selected_building() -> bool:
	for selected in unit_selected:
		if is_instance_valid(selected) and selected.is_in_group("Building"):
			return true
	return false

func _selected_buildings_allow_commands() -> bool:
	var buildings: Array = []
	for selected in unit_selected:
		if not is_instance_valid(selected) or not selected.is_in_group("Building"):
			return false
		buildings.append(selected)
	return not buildings.is_empty() and _are_buildings_same_type(buildings)

func _selection_allows_building_command_lookup() -> bool:
	if unit_selected.is_empty():
		return false
	for selected in unit_selected:
		if not is_instance_valid(selected) or not selected.is_in_group("Building"):
			return false
	return true

func _are_buildings_same_type(buildings: Array) -> bool:
	if buildings.is_empty():
		return false
	var first_name := _get_building_type_name(buildings[0])
	for building in buildings:
		if _get_building_type_name(building) != first_name:
			return false
	return true

func _get_building_type_name(building) -> String:
	if is_instance_valid(building) and "building_name" in building:
		return str(building.building_name).strip_edges()
	return str(building.name if is_instance_valid(building) else "").strip_edges()

func _on_build_basic_pressed():
	current_command = CommandMode.NONE
	_try_start_building({
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
		"icon_texture": preload("res://assets/building/building_museum.png"),
		"preview_texture": preload("res://assets/building/building_museum.png"),
		"mineral_cost": 400,
		"gas_cost": 0
	})
	_refresh_command_ui()

func _on_build_supply_pressed():
	current_command = CommandMode.NONE
	_try_start_building({
		"building_name": "공대식당",
		"description": "인구수 제한을 늘려준다",
		"can_produce_students": false,
		"can_produce_units": false,
		"supply_bonus": 8,
		"accepts_resource_dropoff": false,
		"max_hp": 400,
		"build_time": 20.0,
		"footprint_tiles": Vector2i(8, 3),
		"visual_ground_ratio": 0.8,
		"icon_texture": preload("res://assets/building/building_restaurant.png"),
		"preview_texture": preload("res://assets/building/building_restaurant.png"),
		"mineral_cost": 50,
		"gas_cost": 0
	})
	_refresh_command_ui()

func _on_build_excavation_pressed():
	current_command = CommandMode.NONE
	_try_start_building({
		"building_name": "발굴지",
		"display_name": "발굴지",
		"description": "유물을 채취할 수 있다",
		"can_produce_students": false,
		"can_produce_units": false,
		"supply_bonus": 0,
		"accepts_resource_dropoff": false,
		"provides_resource": true,
		"resource_amount": 1000,
		"resource_kind": "artifact",
		"gather_time_override": 3.0,
		"max_hp": 350,
		"build_time": 25.0,
		"footprint_tiles": Vector2i(7, 5),
		"visual_ground_ratio": 1.0,
		"lock_footprint_to_config": true,
		"icon_texture": preload("res://assets/building/excavation_site.png"),
		"preview_texture": preload("res://assets/building/excavation_site.png"),
		"requires_foundation_group": "Ruins",
		"mineral_cost": 75,
		"gas_cost": 0
	})
	_refresh_command_ui()

func _on_build_barracks_pressed():
	current_command = CommandMode.NONE
	if not _has_completed_building("공대식당"):
		_show_hud_notice("공대식당을 먼저 건설해야합니다")
		_refresh_command_ui()
		return
	_try_start_building({
		"building_name": "덕래관",
		"description": "공격유닛을 생산할 수 있다",
		"can_produce_students": false,
		"can_produce_units": true,
		"production_unit_scene": preload("res://scenes/units/graduate_student.tscn"),
		"production_unit_icon": preload("res://icon/M_stduent_icon.png"),
		"production_unit_button_icon_path": "res://assets/btu/M_stduent_btu.png",
		"production_unit_name": "대학원생",
		"production_time": 40.0,
		"production_population_cost": 2,
		"production_mineral_cost": 75,
		"production_gas_cost": 0,
		"supply_bonus": 0,
		"accepts_resource_dropoff": false,
		"max_hp": 1000,
		"build_time": 25.0,
		"footprint_tiles": Vector2i(13, 6),
		"visual_ground_ratio": 0.8,
		"visual_scale_override": 0.256,
		"icon_texture": preload("res://assets/building/building_dok.png"),
		"preview_texture": preload("res://assets/building/building_dok.png"),
		"mineral_cost": 150,
		"gas_cost": 0
	})
	_refresh_command_ui()

func _on_build_army_training_pressed():
	current_command = CommandMode.NONE
	if not _has_completed_building("덕래관"):
		_show_hud_notice("덕래관을 먼저 건설해야합니다")
		_refresh_command_ui()
		return
	_try_start_building({
		"building_name": "훈련소",
		"description": "예비군을 생산할 수 있게 한다",
		"can_produce_students": false,
		"can_produce_units": false,
		"supply_bonus": 0,
		"accepts_resource_dropoff": false,
		"max_hp": 1000,
		"build_time": 30.0,
		"footprint_tiles": Vector2i(13, 6),
		"visual_ground_ratio": 0.8,
		"visual_scale_override": 0.256,
		"icon_texture": preload("res://assets/building/building_armitraing.png"),
		"preview_texture": preload("res://assets/building/building_armitraing.png"),
		"mineral_cost": 150,
		"gas_cost": 50
	})
	_refresh_command_ui()

func _try_start_building(building_config: Dictionary) -> bool:
	var hud = _get_hud()
	if hud and hud.has_method("get_cost_failure_message"):
		var cost_message = hud.get_cost_failure_message(building_config.get("mineral_cost", 0), building_config.get("gas_cost", 0))
		if not cost_message.is_empty():
			hud.show_notice(cost_message)
			return false
	var placement = get_tree().get_first_node_in_group("BuildingPlacement")
	if placement and placement.has_method("start_building"):
		placement.start_building(building_config)
		return true
	return false

func _show_hud_notice(text: String):
	var hud = _get_hud()
	if hud and hud.has_method("show_notice"):
		hud.show_notice(text)

func _get_hud():
	return get_tree().current_scene.find_child("HUD", true, false) if get_tree().current_scene else null

func _has_completed_building(building_name: String) -> bool:
	for building in get_tree().get_nodes_in_group("Building"):
		if is_instance_valid(building) and "building_name" in building and building.building_name == building_name:
			if not ("is_under_construction" in building) or not building.is_under_construction:
				return true
	return false

func _find_nearest_dropoff(from_pos: Vector2):
	var closest = null
	var min_dist = INF
	for dropoff in get_tree().get_nodes_in_group("ResourceDropoff"):
		if _is_valid_resource_dropoff(dropoff):
			var d = _get_dropoff_distance(dropoff, from_pos)
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

func _generate_circular_formation(center: Vector2, count: int, gap: float):
	var points = [center] 
	if count <= 1: return points
	var current_count = 1
	var layer = 1
	while current_count < count:
		var radius = layer * gap
		var capacity = int(floor((2 * PI * radius) / gap))
		var num_in_layer = min(capacity, count - current_count)
		for i in range(num_in_layer):
			var angle = i * (2 * PI / num_in_layer)
			var pos = center + Vector2(cos(angle), sin(angle)) * radius
			points.append(pos)
			current_count += 1
		layer += 1
	return points
