extends Control

var minerals = 50
var gas = 0
var current_pop = 4
var max_pop = 10

const MESSAGE_VISIBLE_TIME := 5.0
const MESSAGE_FADE_TIME := 1.5
const MAX_MESSAGES := 5
const MESSAGE_LINE_HEIGHT := 22.0
const LAPIS_BOX_PATH := "res://icon/lapis_box.png"
const RELICS_BOX_PATH := "res://icon/relics_box.png"
const POPULATION_BOX_PATH := "res://icon/population_box.png"
const TOP_BAR_ICON_SIZE := Vector2(24, 24)

@onready var mineral_label = $TopBar/Minerals
@onready var gas_label = $TopBar/Gas
@onready var pop_label = $TopBar/Population

var notice_messages: Array = []
var message_layer: PanelContainer
var message_container: VBoxContainer

func _ready():
	if _is_test_mode_enabled():
		minerals = 10000
		gas = 10000
	set_anchors_preset(Control.PRESET_FULL_RECT)
	offset_left = 0.0
	offset_top = 0.0
	offset_right = 0.0
	offset_bottom = 0.0
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	get_viewport().size_changed.connect(_position_top_bar)
	_setup_top_bar_icons()
	_create_notice_area()
	_position_top_bar()
	update_ui()

func _is_test_mode_enabled() -> bool:
	return get_tree().root.has_meta("test_mode") and bool(get_tree().root.get_meta("test_mode"))

func _process(delta):
	if Input.is_action_just_pressed("ui_accept"):
		add_resource(50, 0)
	_position_notice_area()
	_update_notice_messages(delta)

func add_resource(m, g):
	minerals += m
	gas += g
	update_ui()

func can_afford(mineral_cost: int, gas_cost: int = 0) -> bool:
	return minerals >= mineral_cost and gas >= gas_cost

func get_cost_failure_message(mineral_cost: int, gas_cost: int = 0) -> String:
	if minerals < mineral_cost:
		play_ui_alert("mineral")
		return "청금석이 부족합니다"
	if gas < gas_cost:
		play_ui_alert("gas")
		return "유물이 부족합니다"
	return ""

func spend_resource(mineral_cost: int, gas_cost: int = 0) -> bool:
	if not can_afford(mineral_cost, gas_cost):
		return false
	minerals -= mineral_cost
	gas -= gas_cost
	update_ui()
	return true

func can_reserve_population(pop_cost: int) -> bool:
	return current_pop + pop_cost <= max_pop

func reserve_population(pop_cost: int) -> bool:
	if not can_reserve_population(pop_cost):
		play_ui_alert("population")
		return false
	current_pop += pop_cost
	update_ui()
	return true

func reserve_population_or_notice(pop_cost: int) -> bool:
	if not can_reserve_population(pop_cost):
		play_ui_alert("population")
		show_notice("인구수가 부족합니다")
		return false
	current_pop += pop_cost
	update_ui()
	return true

func release_population(pop_cost: int):
	current_pop = max(0, current_pop - pop_cost)
	update_ui()

func play_ui_alert(alert_type: String):
	var manager = get_tree().get_first_node_in_group("UnitManager")
	if manager and manager.has_method("play_ui_alert"):
		manager.play_ui_alert(alert_type)

func add_max_population(amount: int):
	max_pop += amount
	update_ui()

func remove_max_population(amount: int):
	max_pop = max(0, max_pop - amount)
	update_ui()

func update_ui():
	mineral_label.text = ": " + str(minerals)
	gas_label.text = ": " + str(gas)
	pop_label.text = ": %d/%d" % [current_pop, max_pop]

func _setup_top_bar_icons():
	_add_icon_before_label("LapisIcon", LAPIS_BOX_PATH, mineral_label)
	_add_icon_before_label("RelicsIcon", RELICS_BOX_PATH, gas_label)
	_add_icon_before_label("PopulationIcon", POPULATION_BOX_PATH, pop_label)

func _add_icon_before_label(icon_name: String, texture_path: String, label: Label):
	if not label:
		return
	var top_bar = label.get_parent()
	if not top_bar:
		return
	if top_bar.get_node_or_null(icon_name):
		return
	if not ResourceLoader.exists(texture_path):
		return
	var icon = TextureRect.new()
	icon.name = icon_name
	icon.texture = load(texture_path)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.custom_minimum_size = TOP_BAR_ICON_SIZE
	icon.size = TOP_BAR_ICON_SIZE
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_bar.add_child(icon)
	top_bar.move_child(icon, label.get_index())

func show_notice(text: String):
	if text.is_empty() or not message_layer:
		return
	while notice_messages.size() >= MAX_MESSAGES:
		var oldest = notice_messages.pop_front()
		if oldest.has("label") and is_instance_valid(oldest["label"]):
			oldest["label"].queue_free()

	var label = Label.new()
	label.text = text
	label.modulate = Color(1.0, 0.86, 0.28, 1.0)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 4)
	message_layer.add_child(label)
	notice_messages.append({"label": label, "age": 0.0})
	_layout_notice_messages()

func _create_notice_area():
	var old_message_log = get_node_or_null("BottomPanel/InfoPanel/MessageLog")
	if old_message_log:
		old_message_log.hide()

	message_layer = PanelContainer.new()
	message_layer.name = "NoticeMessageLog"
	message_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	message_layer.clip_contents = false
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0)
	message_layer.add_theme_stylebox_override("panel", style)
	add_child(message_layer)

	message_container = VBoxContainer.new()
	message_container.visible = false
	message_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	message_container.alignment = BoxContainer.ALIGNMENT_END
	message_container.add_theme_constant_override("separation", 0)
	message_layer.add_child(message_container)
	call_deferred("_position_notice_area")

func _position_notice_area():
	if not message_layer:
		return
	var bottom_panel = get_node_or_null("BottomPanel")
	var info_panel = get_node_or_null("BottomPanel/InfoPanel")
	if not bottom_panel or not info_panel:
		return

	var width = max(240.0, info_panel.size.x - 24.0)
	var height = max(24.0, bottom_panel.size.y - info_panel.size.y - 6.0)
	message_layer.position = Vector2(bottom_panel.position.x + info_panel.position.x + 12.0, 448.0)
	message_layer.size = Vector2(width, height)
	if message_container:
		message_container.size = message_layer.size
	_layout_notice_messages()

func _layout_notice_messages():
	if not message_layer:
		return
	for i in range(notice_messages.size()):
		var label = notice_messages[i].get("label")
		if not is_instance_valid(label):
			continue
		var older_count = notice_messages.size() - 1 - i
		label.position = Vector2(0.0, -older_count * MESSAGE_LINE_HEIGHT)
		label.size = Vector2(message_layer.size.x, MESSAGE_LINE_HEIGHT)

func _update_notice_messages(delta: float):
	for i in range(notice_messages.size() - 1, -1, -1):
		var entry = notice_messages[i]
		entry["age"] += delta
		var age = float(entry["age"])
		var label = entry["label"]
		if is_instance_valid(label) and age > MESSAGE_VISIBLE_TIME:
			var fade_ratio = clamp((age - MESSAGE_VISIBLE_TIME) / MESSAGE_FADE_TIME, 0.0, 1.0)
			label.modulate.a = 1.0 - fade_ratio
		if age >= MESSAGE_VISIBLE_TIME + MESSAGE_FADE_TIME:
			if is_instance_valid(label):
				label.queue_free()
			notice_messages.remove_at(i)
			_layout_notice_messages()

func _position_top_bar():
	var top_bar = $TopBar
	var viewport_size = get_viewport_rect().size
	var bar_size = Vector2(460.0, 28.0)

	top_bar.set_anchors_preset(Control.PRESET_TOP_LEFT)
	top_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_bar.position = Vector2(max(0.0, viewport_size.x - bar_size.x - 12.0), 8.0)
	top_bar.size = bar_size
	top_bar.alignment = BoxContainer.ALIGNMENT_END
	for child in top_bar.get_children():
		if child is Control:
			child.mouse_filter = Control.MOUSE_FILTER_IGNORE

func _on_unit_selected(units):
	$BottomPanel/UnitInfo.display_units(units)
	$BottomPanel/CommandCenter.update_buttons(units)
