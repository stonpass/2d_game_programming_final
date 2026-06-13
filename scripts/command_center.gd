extends PanelContainer

@onready var button_grid = $ButtonGrid

const TOOLTIP_MARGIN := Vector2(18, 18)
const TOOLTIP_HIT_PADDING := 12.0
const BUTTON_SIZE := 64.0
const BUTTON_GAP := 3.0

var tooltip_layer: CanvasLayer
var tooltip_panel: PanelContainer
var tooltip_label: RichTextLabel
var tooltip_owner: Button = null
var tooltip_text_cache: String = ""

func _ready():
	add_to_group("CommandCenter")
	tooltip_layer = CanvasLayer.new()
	tooltip_layer.name = "CommandTooltipLayer"
	tooltip_layer.layer = 127
	tooltip_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(tooltip_layer)

	tooltip_panel = PanelContainer.new()
	tooltip_panel.visible = false
	tooltip_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.02, 0.02, 0.02, 0.96)
	panel_style.border_color = Color(0.55, 0.55, 0.55, 1.0)
	panel_style.set_border_width_all(1)
	panel_style.set_content_margin_all(8)
	tooltip_panel.add_theme_stylebox_override("panel", panel_style)
	tooltip_layer.add_child(tooltip_panel)

	tooltip_label = RichTextLabel.new()
	tooltip_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tooltip_label.bbcode_enabled = true
	tooltip_label.fit_content = true
	tooltip_label.scroll_active = false
	tooltip_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tooltip_label.custom_minimum_size = Vector2(180, 0)
	tooltip_panel.add_child(tooltip_label)
	_setup_button_grid()
	clear_window()

func _process(_delta):
	_update_button_highlights()
	_update_tooltip()

func clear_window():
	_hide_tooltip()
	if button_grid:
		for child in button_grid.get_children():
			child.queue_free()

func update_buttons(selected_targets: Array):
	update_command_window(selected_targets)

func update_command_window(selected_targets: Array):
	clear_window()
	_setup_button_grid()
	if selected_targets.is_empty(): return
	if _is_mixed_building_selection(selected_targets): return
	var leader = selected_targets[0]
	if not leader.has_method("get_current_buttons"): return
	var current_buttons = leader.get_current_buttons()
	var selected_ids := []
	for target in selected_targets:
		if is_instance_valid(target):
			selected_ids.append(target.get_instance_id())
	
	var grid_slots: Array = []
	grid_slots.resize(9)
	grid_slots.fill(null)
	
	for btn_data in current_buttons:
		var slot_idx = btn_data.get("index", 0)
		if slot_idx >= 0 and slot_idx < 9:
			grid_slots[slot_idx] = btn_data

	for i in range(9):
		var data = grid_slots[i]
		if data != null:
			var new_btn = Button.new()
			new_btn.text = "" 
			new_btn.tooltip_text = ""
			
			if data.has("icon_path") and data["icon_path"] != "":
				var tex = load(data["icon_path"])
				if tex:
					new_btn.icon = tex
					new_btn.expand_icon = true 
			new_btn.custom_minimum_size = Vector2(60, 60)
			new_btn.custom_minimum_size = Vector2(BUTTON_SIZE, BUTTON_SIZE)
			new_btn.size = Vector2(BUTTON_SIZE, BUTTON_SIZE)
			new_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			new_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			
			# ★ 중요: 이동 버튼은 단축키(shortcut)를 등록하지 않아 M키 작동을 원천 차단합니다.
			if data.has("key") and data["function"] != "_on_move_pressed" and data["key"] != KEY_ESCAPE:
				var shortcut = Shortcut.new()
				var input_key = InputEventKey.new()
				input_key.keycode = data["key"]
				shortcut.events.append(input_key)
				new_btn.shortcut = shortcut 
			
			var func_name = data["function"]
			var manager = get_tree().get_first_node_in_group("UnitManager")
			
			new_btn.set_meta("function_name", func_name)
			if data.has("key"):
				new_btn.set_meta("shortcut_key", int(data["key"]))
			new_btn.set_meta("tooltip", _append_shortcut_line(_get_button_tooltip(func_name, data), int(data.get("key", 0))))
			var is_disabled = data.get("disabled", false)
			if manager and manager.has_method("is_button_enabled_for_selection"):
				is_disabled = not manager.is_button_enabled_for_selection(func_name, is_disabled)
			if is_disabled:
				new_btn.disabled = true
				new_btn.self_modulate = Color(0.35, 0.35, 0.35, 1.0)
			_update_button_condition_state(new_btn)
			
			# [정지 버튼 누름 피드백] 마우스로 누르고 있는 동안 5배 밝기
			if func_name == "_on_stop_pressed":
				new_btn.button_down.connect(Callable(self, "_set_button_holding").bind(new_btn.get_instance_id(), true))
				new_btn.button_up.connect(Callable(self, "_set_button_holding").bind(new_btn.get_instance_id(), false))
			
			if func_name == "change_menu_page":
				var target_page = data["argument"]
				new_btn.pressed.connect(Callable(self, "_play_mouse_click_sound"))
				new_btn.pressed.connect(Callable(self, "_change_leader_menu_page").bind(leader.get_instance_id(), target_page))
			else:
				if manager and manager.has_method(func_name):
					new_btn.button_down.connect(Callable(self, "_call_manager_button_once").bind(new_btn.get_instance_id(), func_name, selected_ids))
					new_btn.pressed.connect(Callable(self, "_call_manager_button_from_press").bind(new_btn.get_instance_id(), func_name, selected_ids))
				elif leader.has_method(func_name):
					new_btn.button_down.connect(Callable(self, "_call_leader_button_once").bind(new_btn.get_instance_id(), leader.get_instance_id(), func_name))
					new_btn.pressed.connect(Callable(self, "_call_leader_button_from_press").bind(new_btn.get_instance_id(), leader.get_instance_id(), func_name))
			
			button_grid.add_child(new_btn)
		else:
			var dummy = Control.new()
			dummy.custom_minimum_size = Vector2(BUTTON_SIZE, BUTTON_SIZE)
			dummy.size = Vector2(BUTTON_SIZE, BUTTON_SIZE)
			dummy.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			dummy.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			button_grid.add_child(dummy)

func _is_mixed_building_selection(selected_targets: Array) -> bool:
	if selected_targets.size() <= 1:
		return false
	var building_count := 0
	var first_name := ""
	for target in selected_targets:
		if not is_instance_valid(target) or not target.is_in_group("Building"):
			return false
		building_count += 1
		var building_name = str(target.building_name if "building_name" in target else target.name).strip_edges()
		if first_name.is_empty():
			first_name = building_name
		elif building_name != first_name:
			return true
	return building_count > 1 and false

func _set_button_holding(button_id: int, is_holding: bool):
	var button = instance_from_id(button_id)
	if button and button is Button:
		button.set_meta("is_holding", is_holding)

func _change_leader_menu_page(leader_id: int, target_page):
	_play_mouse_click_sound()
	var leader = instance_from_id(leader_id)
	if is_instance_valid(leader) and "current_menu_page" in leader:
		leader.current_menu_page = target_page
	_refresh_from_current_selection()

func _call_leader_button(leader_id: int, func_name: String):
	_play_mouse_click_sound()
	var leader = instance_from_id(leader_id)
	if is_instance_valid(leader) and leader.has_method(func_name):
		leader.call(func_name)
	_refresh_from_current_selection()

func _call_leader_button_once(button_id: int, leader_id: int, func_name: String):
	var button = instance_from_id(button_id)
	if not button or not (button is Button) or button.disabled:
		return
	if button.get_meta("pressed_handled", false):
		return
	button.set_meta("pressed_handled", true)
	_call_leader_button(leader_id, func_name)

func _call_leader_button_from_press(button_id: int, leader_id: int, func_name: String):
	var button = instance_from_id(button_id)
	if button and (button is Button) and button.get_meta("pressed_handled", false):
		button.set_meta("pressed_handled", false)
		return
	_call_leader_button(leader_id, func_name)

func _call_manager_button(func_name: String, selected_ids: Array = []):
	_play_mouse_click_sound()
	var manager = get_tree().get_first_node_in_group("UnitManager")
	if manager and manager.has_method("is_snapshot_button_command") and manager.is_snapshot_button_command(func_name) and manager.has_method("issue_selection_button_command_for_ids"):
		manager.issue_selection_button_command_for_ids(func_name, selected_ids)
	elif manager and manager.has_method(func_name):
		manager.call(func_name)
	_refresh_from_current_selection()

func _call_manager_button_once(button_id: int, func_name: String, selected_ids: Array = []):
	var button = instance_from_id(button_id)
	if not button or not (button is Button) or button.disabled:
		return
	if button.get_meta("pressed_handled", false):
		return
	button.set_meta("pressed_handled", true)
	_call_manager_button(func_name, selected_ids)

func _call_manager_button_from_press(button_id: int, func_name: String, selected_ids: Array = []):
	var button = instance_from_id(button_id)
	if button and (button is Button) and button.get_meta("pressed_handled", false):
		button.set_meta("pressed_handled", false)
		return
	_call_manager_button(func_name, selected_ids)

func _play_mouse_click_sound():
	var manager = get_tree().get_first_node_in_group("UnitManager")
	if manager and manager.has_method("play_mouse_click_sound"):
		manager.play_mouse_click_sound()

func _refresh_from_current_selection():
	var manager = get_tree().get_first_node_in_group("UnitManager")
	if manager and "unit_selected" in manager:
		update_command_window(manager.unit_selected)

func _setup_button_grid():
	if not button_grid:
		return
	var grid_size = Vector2((BUTTON_SIZE * 3.0) + (BUTTON_GAP * 2.0), (BUTTON_SIZE * 3.0) + (BUTTON_GAP * 2.0))
	button_grid.custom_minimum_size = grid_size
	button_grid.size = grid_size
	button_grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	button_grid.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button_grid.add_theme_constant_override("h_separation", int(BUTTON_GAP))
	button_grid.add_theme_constant_override("v_separation", int(BUTTON_GAP))
	button_grid.columns = 3

# 깔끔하게 정리된 실시간 5배 밝기 제어 루틴 (5, 5, 5, 5 규격)
func _update_tooltip():
	if not button_grid or not tooltip_panel:
		return

	var mouse_pos = get_viewport().get_mouse_position()
	var hovered_button = _find_button_under_mouse(mouse_pos)
	if hovered_button and hovered_button.has_meta("tooltip"):
		_update_button_condition_state(hovered_button)
		_show_tooltip(hovered_button, str(hovered_button.get_meta("tooltip")), mouse_pos)
	else:
		_hide_tooltip()

func _find_button_under_mouse(mouse_pos: Vector2) -> Button:
	for child in button_grid.get_children():
		if child is Button and child.visible and child.has_meta("tooltip"):
			if child.get_global_rect().grow(TOOLTIP_HIT_PADDING).has_point(mouse_pos):
				return child
	return null

func _show_tooltip(button: Button, text: String, mouse_pos: Vector2):
	if text.is_empty():
		_hide_tooltip()
		return

	if tooltip_owner != button or tooltip_text_cache != text:
		tooltip_owner = button
		tooltip_text_cache = text
		tooltip_label.clear()
		tooltip_label.parse_bbcode(text)
		tooltip_panel.reset_size()

	var desired_size = tooltip_panel.get_combined_minimum_size()
	var viewport_size = get_viewport_rect().size
	var next_pos = mouse_pos + TOOLTIP_MARGIN
	if next_pos.x + desired_size.x > viewport_size.x:
		next_pos.x = mouse_pos.x - desired_size.x - TOOLTIP_MARGIN.x
	if next_pos.y + desired_size.y > viewport_size.y:
		next_pos.y = mouse_pos.y - desired_size.y - TOOLTIP_MARGIN.y
	next_pos.x = clamp(next_pos.x, 0.0, max(0.0, viewport_size.x - desired_size.x))
	next_pos.y = clamp(next_pos.y, 0.0, max(0.0, viewport_size.y - desired_size.y))

	tooltip_panel.position = next_pos
	tooltip_panel.visible = true

func _hide_tooltip():
	tooltip_owner = null
	tooltip_text_cache = ""
	if tooltip_panel:
		tooltip_panel.visible = false

func _append_shortcut_line(text: String, keycode: int) -> String:
	if keycode == 0:
		return text
	var label := _get_shortcut_label(keycode)
	if label.is_empty():
		return text
	if text.to_upper().contains(label.to_upper()):
		return text
	var prefix := "\n" if not text.is_empty() else ""
	return text + prefix + "[color=#ff9f33][lb]%s[rb][/color]" % label

func _append_button_shortcut(text: String, button: Button) -> String:
	if not button or not button.has_meta("shortcut_key"):
		return text
	return _append_shortcut_line(text, int(button.get_meta("shortcut_key")))

func _get_shortcut_label(keycode: int) -> String:
	var label := OS.get_keycode_string(keycode)
	if label.is_empty():
		return ""
	if label == "Escape":
		return "ESC"
	if label.length() == 1:
		return label.to_upper()
	return label

func _get_button_tooltip(func_name: String, data: Dictionary) -> String:
	if func_name == "change_menu_page" and data.has("tooltip"):
		return str(data.get("tooltip", ""))
	if func_name == "_on_build_basic_pressed":
		return "[color=#ffd84a]행소박물관[/color]\n건설시간 [color=#56a8ff]40초[/color]\n필요자원 [color=#56a8ff]400/0[/color]\n인구수 제한 [color=#56a8ff]+10[/color]"
	if func_name == "_on_build_supply_pressed":
		return "[color=#ffd84a]공대식당[/color]\n건설시간 [color=#56a8ff]20초[/color]\n필요자원 [color=#56a8ff]50/0[/color]\n인구수 제한 [color=#56a8ff]+8[/color]"
	if func_name == "_on_build_barracks_pressed":
		return _get_fixed_barracks_tooltip()
	if func_name == "_on_build_army_training_pressed":
		return _get_training_tooltip()
	if func_name == "_on_build_excavation_pressed":
		return "[color=#ffd84a]발굴지[/color]\n건설시간 [color=#56a8ff]25초[/color]\n필요자원 [color=#56a8ff]75/0[/color]\n유물을 채취할 수 있다\n필요조건 [color=#56a8ff]유적지[/color] 위에 건설"
	match func_name:
		"_on_build_basic_pressed":
			return "[color=#ffd84a]행소박물관[/color]\n건설시간 [color=#56a8ff]40초[/color]\n필요 자원 [color=#56a8ff]400/0[/color]\n인구수 제한 [color=#56a8ff]+10[/color]"
		"_on_build_supply_pressed":
			return "[color=#ffd84a]공대식당[/color]\n건설시간 [color=#56a8ff]20초[/color]\n필요 자원 [color=#56a8ff]50/0[/color]\n인구수 제한 [color=#56a8ff]+8[/color]"
		"_on_build_barracks_pressed":
			return _get_barracks_tooltip()
		"_on_build_excavation_pressed":
			return "[color=#ffd84a]발굴지[/color]\n건설시간 [color=#56a8ff]25초[/color]\n필요 자원 [color=#56a8ff]75/0[/color]\n유물을 채취할 수 있다\n필요조건 [color=#56a8ff]유적지[/color] 위에 건설"
		_:
			return str(data.get("tooltip", ""))

func _get_barracks_tooltip() -> String:
	var condition_color = "#56a8ff" if _is_barracks_condition_met() else "#ff4a4a"
	return "[color=#ffd84a]덕래관[/color]\n건설시간 [color=#56a8ff]25초[/color]\n필요 자원 [color=#56a8ff]150/0[/color]\n공격유닛을 생산할 수 있다\n필요조건 [color=%s]공대식당[/color] 건설" % condition_color

func _is_barracks_condition_met() -> bool:
	var manager = get_tree().get_first_node_in_group("UnitManager")
	if manager and manager.has_method("_has_completed_building"):
		return manager._has_completed_building("공대식당")
	return false

func _get_fixed_barracks_tooltip() -> String:
	var condition_color = "#56a8ff" if _is_barracks_condition_met() else "#ff4a4a"
	return "[color=#ffd84a]덕래관[/color]\n건설시간 [color=#56a8ff]25초[/color]\n필요자원 [color=#56a8ff]150/0[/color]\n[color=#56a8ff]공격유닛[/color]을 생산 할 수 있다\n필요조건 [color=%s]공대식당[/color] 건설" % condition_color

func _get_training_tooltip() -> String:
	var condition_color = "#56a8ff" if _is_training_condition_met() else "#ff4a4a"
	return "[color=#ffd84a]훈련소[/color]\n건설시간: [color=#56a8ff]30초[/color]\n필요자원 : [color=#56a8ff]150/50[/color]\n필요조건 : [color=%s]덕래관[/color] 건설" % condition_color

func _is_training_condition_met() -> bool:
	var manager = get_tree().get_first_node_in_group("UnitManager")
	if manager and manager.has_method("_has_completed_building"):
		return manager._has_completed_building("덕래관")
	return false

func _update_button_condition_state(button: Button):
	if button.disabled:
		button.self_modulate = Color(0.35, 0.35, 0.35, 1)
		return
	var func_name = str(button.get_meta("function_name", ""))
	if func_name == "_on_build_barracks_pressed":
		var is_met = _is_barracks_condition_met()
		button.set_meta("tooltip", _append_button_shortcut(_get_fixed_barracks_tooltip(), button))
		button.self_modulate = Color(1, 1, 1, 1) if is_met else Color(0.35, 0.35, 0.35, 1)
	elif func_name == "_on_build_army_training_pressed":
		var training_condition_met = _is_training_condition_met()
		button.set_meta("tooltip", _append_button_shortcut(_get_training_tooltip(), button))
		button.self_modulate = Color(1, 1, 1, 1) if training_condition_met else Color(0.35, 0.35, 0.35, 1)
	else:
		button.self_modulate = Color(1, 1, 1, 1)

func _update_button_highlights():
	var manager = get_tree().get_first_node_in_group("UnitManager")
	if not manager or not button_grid: return
		
	var current_mode = manager.current_command 
	
	# 우클릭이 현재 물리적으로 눌려있는지 여부 판정
	var is_right_click_holding = Input.is_action_pressed("right_click")
	# S 키가 현재 물리적으로 눌려있는지 여부 판정
	var is_s_key_holding = Input.is_key_pressed(KEY_S)
	# A 키가 현재 물리적으로 눌려있는지 여부 판정
	var is_a_key_holding = Input.is_key_pressed(KEY_A)
	
	for child in button_grid.get_children():
		if child is Button and child.has_meta("function_name"):
			_update_button_condition_state(child)
			var f_name = child.get_meta("function_name")
			
			match f_name:
				"_on_move_pressed":
					# 1. 이동 모드가 켜져 있거나, 2. 맵에 우클릭을 유지하고 있을 때 5배 밝기
					if current_mode == 1 or is_right_click_holding:
						child.modulate = Color(5.0, 5.0, 5.0, 5.0)
					else:
						child.modulate = Color(1.0, 1.0, 1.0, 1.0)
						
				"_on_stop_pressed":
					# 1. S키를 누르고 있거나, 2. 마우스로 정지 버튼을 누르고 있을 때 5배 밝기
					if is_s_key_holding or child.get_meta("is_holding", false):
						child.modulate = Color(5.0, 5.0, 5.0, 5.0)
					else:
						child.modulate = Color(1.0, 1.0, 1.0, 1.0)
						
				"_on_attack_pressed":
					# 1. 공격 모드가 켜져 있거나, 2. A키 단축키를 누르고 있을 때 5배 밝기
					if current_mode == 2 or is_a_key_holding:
						child.modulate = Color(5.0, 5.0, 5.0, 5.0)
					else:
						child.modulate = Color(1.0, 1.0, 1.0, 1.0)
