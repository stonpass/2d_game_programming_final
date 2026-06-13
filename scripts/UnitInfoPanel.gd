extends Panel

const ICON_SLOT_SCENE = preload("res://scenes/ui/unitlcon_slot.tscn")
const LAB_BADGE_TEXTURE = preload("res://assets/btu/technic_btu.png")

@onready var single_view = $SingleUnitView
@onready var multi_view = $MultiUnitView
@onready var unit_icon = $SingleUnitView/UnitIcon
@onready var unit_name_label = $SingleUnitView/VBoxContainer/UnitName
@onready var kill_count_label = $SingleUnitView/VBoxContainer/KillCount
@onready var upgrade_label = $SingleUnitView/VBoxContainer/UpgradeStatus

var selected_objects: Array = []
var progress_bar: ProgressBar
var hp_bar: ProgressBar
var mana_bar: ProgressBar
var hp_value_label: Label
var detail_text_label: RichTextLabel
var production_queue_view: Control
var production_slots: Array = []
var production_slot_panels: Array = []
var upgrade_icon_row: HBoxContainer
var upgrade_icons: Array = []
var upgrade_tooltip_layer: CanvasLayer
var upgrade_tooltip_panel: PanelContainer
var upgrade_tooltip_label: RichTextLabel
var upgrade_tooltip_owner: Control = null
var upgrade_tooltip_text_cache: String = ""

const PRODUCTION_QUEUE_POS := Vector2(235, 34)
const PRODUCTION_BAR_POS := Vector2(235, 87)
const PRODUCTION_SLOT_GAP := 6.0
const PRODUCTION_BAR_SIZE := Vector2(175, 10)
const CONSTRUCTION_BAR_POS := Vector2(37, 122)
const CONSTRUCTION_BAR_SIZE := Vector2(220, 16)
const DEFAULT_ICON_POS := Vector2(37, 1)
const DEFAULT_ICON_SIZE := Vector2(80, 80)
const RESOURCE_ICON_POS := Vector2(17, -8)
const RESOURCE_ICON_SIZE := Vector2(120, 100)
const MINERAL_ICON_POS := Vector2(-34, -36)
const MINERAL_ICON_SIZE := Vector2(220, 165)
const BUILDING_ICON_POS := Vector2(37, -12)
const BUILDING_ICON_SIZE := Vector2(160, 80)
const DEFAULT_HP_BAR_POS := Vector2(37, 82)
const DEFAULT_HP_BAR_SIZE := Vector2(80, 10)
const DEFAULT_MANA_BAR_POS := Vector2(37, 78)
const DEFAULT_MANA_BAR_SIZE := Vector2(80, 4)
const BUILDING_HP_BAR_POS := Vector2(37, 70)
const BUILDING_HP_BAR_SIZE := Vector2(160, 10)
const DEFAULT_HP_LABEL_POS := Vector2(37, 94)
const RESOURCE_AMOUNT_LABEL_POS := Vector2(-12, 79)
const MINERAL_AMOUNT_LABEL_POS := Vector2(-10, 91)
const BUILDING_HP_LABEL_POS := Vector2(37, 82)
const UPGRADE_TOOLTIP_MARGIN := Vector2(18, 18)

func _ready():
	unit_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	unit_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	production_queue_view = Control.new()
	production_queue_view.position = Vector2(37, 1)
	production_queue_view.custom_minimum_size = Vector2(220, 50)
	single_view.add_child(production_queue_view)
	_create_production_slots()

	progress_bar = ProgressBar.new()
	progress_bar.position = Vector2(37, 122)
	progress_bar.custom_minimum_size = Vector2(220, 16)
	progress_bar.min_value = 0
	progress_bar.max_value = 100
	progress_bar.show_percentage = true
	single_view.add_child(progress_bar)

	hp_bar = ProgressBar.new()
	hp_bar.position = DEFAULT_HP_BAR_POS
	hp_bar.custom_minimum_size = DEFAULT_HP_BAR_SIZE
	hp_bar.min_value = 0
	hp_bar.max_value = 100
	hp_bar.show_percentage = false
	single_view.add_child(hp_bar)

	mana_bar = ProgressBar.new()
	mana_bar.position = DEFAULT_MANA_BAR_POS
	mana_bar.custom_minimum_size = DEFAULT_MANA_BAR_SIZE
	mana_bar.min_value = 0
	mana_bar.max_value = 100
	mana_bar.show_percentage = false
	single_view.add_child(mana_bar)

	hp_value_label = Label.new()
	hp_value_label.position = DEFAULT_HP_LABEL_POS
	hp_value_label.custom_minimum_size = Vector2(110, 18)
	hp_value_label.z_index = 20
	single_view.add_child(hp_value_label)

	detail_text_label = RichTextLabel.new()
	detail_text_label.position = Vector2(226, 0)
	detail_text_label.custom_minimum_size = Vector2(360, 130)
	detail_text_label.bbcode_enabled = true
	detail_text_label.fit_content = true
	detail_text_label.scroll_active = false
	detail_text_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	single_view.add_child(detail_text_label)

	upgrade_icon_row = HBoxContainer.new()
	upgrade_icon_row.position = Vector2(226, 72)
	upgrade_icon_row.custom_minimum_size = Vector2(170, 50)
	upgrade_icon_row.add_theme_constant_override("separation", 6)
	single_view.add_child(upgrade_icon_row)
	for i in range(3):
		var upgrade_icon = TextureRect.new()
		upgrade_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		upgrade_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		upgrade_icon.custom_minimum_size = Vector2(48, 48)
		upgrade_icon.size = Vector2(48, 48)
		upgrade_icon.mouse_filter = Control.MOUSE_FILTER_STOP
		upgrade_icon_row.add_child(upgrade_icon)
		upgrade_icons.append(upgrade_icon)
	_create_upgrade_tooltip()

	clear_info()

func _process(_delta):
	if selected_objects.size() == 1 and is_instance_valid(selected_objects[0]):
		_update_single_object(selected_objects[0])
	_update_upgrade_tooltip()

func clear_info():
	single_view.hide()
	multi_view.hide()
	_set_standard_info_visible(false)
	_hide_production_ui()
	_hide_progress_bar()
	_hide_hp_ui()
	_hide_mana_bar()
	_hide_detail_text()
	_hide_upgrade_icons()
	for child in multi_view.get_children():
		child.queue_free()

func display_units(selected_units: Array):
	selected_objects = selected_units.duplicate()
	clear_info()
	if selected_units.is_empty():
		return
	if selected_units.size() == 1:
		_show_single_object(selected_units[0])
	else:
		_show_multi_units(selected_units)

func _show_single_object(object):
	if not is_instance_valid(object):
		return
	if object.is_in_group("ResourceDeposit") or object.is_in_group("Ruins"):
		_show_single_resource(object)
	elif object.is_in_group("Building"):
		_show_single_building(object)
	else:
		_show_single_unit(object)

func _update_single_object(object):
	if not single_view.visible:
		return
	_show_single_object(object)

func _show_single_unit(unit):
	single_view.show()
	_set_standard_info_visible(true)
	_hide_production_ui()
	_hide_progress_bar()
	_hide_detail_text()
	_set_icon_layout(DEFAULT_ICON_POS, DEFAULT_ICON_SIZE)
	unit_icon.texture = unit.icon_texture if "icon_texture" in unit else null
	unit_name_label.text = "이름: " + str(unit.unit_name if "unit_name" in unit else unit.name)
	kill_count_label.text = "처치: " + str(unit.kills if "kills" in unit else 0)
	upgrade_label.text = "강화: " + str(unit.upgrade_level_name if "upgrade_level_name" in unit else "-")
	unit_icon.self_modulate = _get_health_color(unit)
	unit_name_label.text = str(unit.unit_name if "unit_name" in unit else unit.name)
	kill_count_label.text = "%d킬" % int(unit.kills if "kills" in unit else 0)
	upgrade_label.text = ""
	upgrade_label.hide()
	_update_hp_bar(unit)
	_update_mana_bar(unit)
	_update_upgrade_icons(unit)

func _show_single_resource(resource):
	single_view.show()
	_set_standard_info_visible(true)
	_set_text_labels_visible(false)
	_hide_upgrade_icons()
	_hide_production_ui()
	_hide_progress_bar()
	var uses_standard_resource_icon = resource.is_in_group("Ruins") or (resource.is_in_group("Building") and "building_name" in resource and str(resource.building_name) == "발굴지")
	var icon_pos = RESOURCE_ICON_POS if uses_standard_resource_icon else MINERAL_ICON_POS
	var icon_size = RESOURCE_ICON_SIZE if uses_standard_resource_icon else MINERAL_ICON_SIZE
	var amount_pos = RESOURCE_AMOUNT_LABEL_POS if uses_standard_resource_icon else MINERAL_AMOUNT_LABEL_POS
	_set_icon_layout(icon_pos, icon_size)
	unit_icon.texture = resource.icon_texture if "icon_texture" in resource else null
	unit_icon.self_modulate = Color.GREEN
	if hp_bar:
		hp_bar.hide()
	_hide_mana_bar()
	if hp_value_label:
		hp_value_label.position = amount_pos
		hp_value_label.custom_minimum_size = Vector2(150, 18)
		hp_value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hp_value_label.show()
		var current_amount = int(resource.resource_amount if "resource_amount" in resource else 0)
		var max_amount = current_amount
		if resource.has_method("get_max_resource_amount"):
			max_amount = int(resource.get_max_resource_amount())
		elif "max_resource_amount" in resource:
			max_amount = int(resource.max_resource_amount)
		hp_value_label.text = "%d/%d" % [current_amount, max(max_amount, current_amount)]
	_show_detail_text(
		"%s\n\n%s" % [
			str(resource.display_name if "display_name" in resource else "자원"),
			str(resource.description if "description" in resource else "[color=#ffd84a]학생[/color]으로 청금석을 채취할 수 있다")
		]
	)

func _show_single_building(building):
	single_view.show()
	_set_standard_info_visible(true)
	_set_text_labels_visible(false)
	_hide_upgrade_icons()
	_set_icon_layout(BUILDING_ICON_POS, BUILDING_ICON_SIZE)
	unit_icon.texture = building.icon_texture if "icon_texture" in building else null
	unit_icon.self_modulate = _get_health_color(building)
	_show_detail_text(
		"%s\n\n%s" % [
			str(building.building_name if "building_name" in building else building.name),
			str(building.description if "description" in building else "")
		]
	)
	_update_hp_bar(building)
	_hide_mana_bar()

	if "is_under_construction" in building and building.is_under_construction:
		_hide_production_ui()
		_update_progress_bar(float(building.construction_progress if "construction_progress" in building else 0.0))
	elif building.has_method("get_production_queue_textures") and not building.get_production_queue_textures().is_empty():
		_set_standard_info_visible(true)
		_set_text_labels_visible(true)
		_hide_detail_text()
		var status_text = building.get_production_status_text() if building.has_method("get_production_status_text") else ""
		unit_name_label.text = status_text if not str(status_text).is_empty() else str(building.building_name if "building_name" in building else building.name)
		kill_count_label.text = ""
		upgrade_label.text = ""
		_update_hp_bar(building)
		_hide_mana_bar()
		_update_production_slots(building.get_production_queue_textures())
		_update_production_progress_bar(building.get_production_progress() if building.has_method("get_production_progress") else 0.0)
	elif building.has_method("has_active_upgrade") and building.has_active_upgrade():
		_set_standard_info_visible(true)
		_set_text_labels_visible(true)
		_hide_detail_text()
		var upgrade_status_text = building.get_upgrade_status_text() if building.has_method("get_upgrade_status_text") else ""
		unit_name_label.text = upgrade_status_text if not str(upgrade_status_text).is_empty() else str(building.building_name if "building_name" in building else building.name)
		kill_count_label.text = ""
		upgrade_label.text = ""
		_update_hp_bar(building)
		_hide_mana_bar()
		_update_production_slots(building.get_upgrade_queue_textures() if building.has_method("get_upgrade_queue_textures") else [])
		_update_production_progress_bar(building.get_upgrade_progress() if building.has_method("get_upgrade_progress") else 0.0)
	else:
		_hide_production_ui()
		_hide_progress_bar()

func _show_multi_units(units: Array):
	multi_view.show()
	var icon_size = Vector2(40, 40)
	if units.size() > 20:
		icon_size = Vector2(24, 24)
	elif units.size() > 12:
		icon_size = Vector2(32, 32)

	for object in units:
		if not is_instance_valid(object) or not (object.is_in_group("Unit") or object.is_in_group("Building")):
			continue
		var slot = ICON_SLOT_SCENE.instantiate()
		multi_view.add_child(slot)
		slot.custom_minimum_size = icon_size
		slot.size = icon_size
		slot.clip_contents = true
		var body = slot.get_node("IconBody")
		if body:
			body.texture = object.icon_texture if "icon_texture" in object else null
			body.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			body.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			body.self_modulate = _get_health_color(object)
			body.custom_minimum_size = icon_size
			body.size = icon_size
		var border = slot.get_node_or_null("Border")
		if border:
			border.custom_minimum_size = icon_size
			border.size = icon_size
		if object.is_in_group("Building"):
			_update_multi_building_badges(slot, object, icon_size)

func _update_multi_building_badges(slot: Control, building, icon_size: Vector2):
	if building.has_method("has_completed_laboratory") and building.has_completed_laboratory():
		var lab_badge = TextureRect.new()
		lab_badge.texture = LAB_BADGE_TEXTURE
		lab_badge.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		lab_badge.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		lab_badge.position = Vector2.ZERO
		lab_badge.size = icon_size * 0.38
		lab_badge.custom_minimum_size = lab_badge.size
		lab_badge.z_index = 10
		slot.add_child(lab_badge)
	if building.has_method("get_current_production_icon"):
		var production_icon = building.get_current_production_icon()
		if production_icon:
			var box_size = icon_size * 0.42
			var frame = PanelContainer.new()
			frame.position = Vector2(icon_size.x - box_size.x, icon_size.y - box_size.y)
			frame.size = box_size
			frame.custom_minimum_size = box_size
			frame.z_index = 11
			var style = StyleBoxFlat.new()
			style.bg_color = Color(0.02, 0.02, 0.02, 0.9)
			style.border_color = Color(0.75, 0.85, 0.9, 1.0)
			style.set_border_width_all(1)
			frame.add_theme_stylebox_override("panel", style)
			var icon = TextureRect.new()
			icon.texture = production_icon
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon.size = box_size
			icon.custom_minimum_size = box_size
			frame.add_child(icon)
			slot.add_child(frame)

func _create_production_slots():
	production_slots.clear()
	production_slot_panels.clear()
	for i in range(5):
		var panel = PanelContainer.new()
		var slot_size = Vector2(48, 48) if i == 0 else Vector2(24, 24)
		var slot_x = 0.0
		if i > 0:
			slot_x = 48.0 + PRODUCTION_SLOT_GAP + float(i - 1) * (24.0 + PRODUCTION_SLOT_GAP)
		var slot_y = 0.0 if i == 0 else 24.0
		panel.position = Vector2(slot_x, slot_y)
		panel.custom_minimum_size = slot_size
		panel.size = slot_size
		panel.mouse_filter = Control.MOUSE_FILTER_STOP
		panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		panel.gui_input.connect(Callable(self, "_on_production_slot_gui_input").bind(i))
		var style = StyleBoxFlat.new()
		style.bg_color = Color(0.02, 0.02, 0.02, 0.65)
		style.border_color = Color(0.75, 0.85, 0.9, 0.95)
		style.set_border_width_all(2)
		panel.add_theme_stylebox_override("panel", style)
		var icon = TextureRect.new()
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.custom_minimum_size = slot_size
		icon.size = slot_size
		panel.add_child(icon)
		production_queue_view.add_child(panel)
		production_slot_panels.append(panel)
		production_slots.append(icon)
	production_queue_view.hide()

func _update_production_slots(textures: Array):
	if not production_queue_view:
		return
	production_queue_view.position = PRODUCTION_QUEUE_POS
	production_queue_view.size = Vector2(PRODUCTION_BAR_SIZE.x, 48)
	production_queue_view.custom_minimum_size = Vector2(PRODUCTION_BAR_SIZE.x, 48)
	production_queue_view.show()
	_layout_production_slots()
	for i in range(production_slots.size()):
		var icon = production_slots[i]
		icon.texture = textures[i] if i < textures.size() else null
		icon.self_modulate = Color.WHITE if i < textures.size() else Color(1, 1, 1, 0.15)

func _layout_production_slots():
	for i in range(production_slot_panels.size()):
		var panel = production_slot_panels[i]
		var slot_size = Vector2(48, 48) if i == 0 else Vector2(24, 24)
		var slot_x = 0.0
		if i > 0:
			slot_x = 48.0 + PRODUCTION_SLOT_GAP + float(i - 1) * (24.0 + PRODUCTION_SLOT_GAP)
		var slot_y = 0.0 if i == 0 else 24.0
		panel.position = Vector2(slot_x, slot_y)
		panel.size = slot_size
		panel.custom_minimum_size = slot_size

func _on_production_slot_gui_input(event: InputEvent, index: int):
	if not (event is InputEventMouseButton):
		return
	if event.button_index != MOUSE_BUTTON_LEFT or not event.pressed:
		return
	if selected_objects.size() != 1 or not is_instance_valid(selected_objects[0]):
		return
	var building = selected_objects[0]
	if building.has_method("cancel_production_at_index") and building.cancel_production_at_index(index):
		accept_event()

func _update_progress_bar(progress: float):
	if not progress_bar:
		return
	progress_bar.position = CONSTRUCTION_BAR_POS
	progress_bar.custom_minimum_size = CONSTRUCTION_BAR_SIZE
	progress_bar.size = CONSTRUCTION_BAR_SIZE
	progress_bar.show_percentage = true
	var clamped_progress = clamp(progress, 0.0, 1.0)
	progress_bar.show()
	progress_bar.value = clamped_progress * 100.0
	var background = StyleBoxFlat.new()
	background.bg_color = Color(0.28, 0.28, 0.28, 0.95)
	background.border_color = Color(0.1, 0.45, 1.0, 0.95)
	background.set_border_width_all(1)
	var fill = StyleBoxFlat.new()
	fill.bg_color = Color.RED.lerp(Color.GREEN, clamped_progress)
	progress_bar.add_theme_stylebox_override("background", background)
	progress_bar.add_theme_stylebox_override("fill", fill)

func _update_production_progress_bar(progress: float):
	if not progress_bar:
		return
	progress_bar.position = PRODUCTION_BAR_POS
	progress_bar.custom_minimum_size = PRODUCTION_BAR_SIZE
	progress_bar.size = PRODUCTION_BAR_SIZE
	progress_bar.show_percentage = false
	var clamped_progress = clamp(progress, 0.0, 1.0)
	progress_bar.show()
	progress_bar.value = clamped_progress * 100.0
	var background = StyleBoxFlat.new()
	background.bg_color = Color(0.28, 0.28, 0.28, 0.95)
	background.border_color = Color(0.1, 0.45, 1.0, 0.95)
	background.set_border_width_all(1)
	var fill = StyleBoxFlat.new()
	fill.bg_color = Color.RED.lerp(Color.GREEN, clamped_progress)
	progress_bar.add_theme_stylebox_override("background", background)
	progress_bar.add_theme_stylebox_override("fill", fill)

func _update_hp_bar(object):
	if not hp_bar or not hp_value_label:
		return
	var current_hp = object.hp if "hp" in object else 0
	var max_hp = object.max_hp if "max_hp" in object else 0
	var hp_ratio = clamp(float(current_hp) / float(max(max_hp, 1)), 0.0, 1.0)
	hp_bar.show()
	hp_value_label.show()
	if object.is_in_group("Building"):
		hp_bar.position = BUILDING_HP_BAR_POS
		hp_bar.custom_minimum_size = BUILDING_HP_BAR_SIZE
		hp_bar.size = BUILDING_HP_BAR_SIZE
		hp_value_label.position = BUILDING_HP_LABEL_POS
		hp_value_label.custom_minimum_size = Vector2(BUILDING_HP_BAR_SIZE.x, 18)
	else:
		hp_bar.position = DEFAULT_HP_BAR_POS
		hp_bar.custom_minimum_size = DEFAULT_HP_BAR_SIZE
		hp_bar.size = DEFAULT_HP_BAR_SIZE
		hp_value_label.position = DEFAULT_HP_LABEL_POS
		hp_value_label.custom_minimum_size = Vector2(110, 18)
	hp_bar.value = hp_ratio * 100.0
	hp_value_label.text = "%d/%d" % [current_hp, max_hp]
	var fill = StyleBoxFlat.new()
	fill.bg_color = Color.RED.lerp(Color.GREEN, hp_ratio)
	hp_bar.add_theme_stylebox_override("fill", fill)

func _update_mana_bar(object):
	if not mana_bar:
		return
	if not ("max_mana" in object) or object.max_mana <= 0:
		_hide_mana_bar()
		return
	var current_mana = object.mana if "mana" in object else 0
	var max_mana = object.max_mana
	var mana_ratio = clamp(float(current_mana) / float(max(max_mana, 1)), 0.0, 1.0)
	mana_bar.position = DEFAULT_MANA_BAR_POS
	mana_bar.custom_minimum_size = DEFAULT_MANA_BAR_SIZE
	mana_bar.size = DEFAULT_MANA_BAR_SIZE
	mana_bar.value = mana_ratio * 100.0
	var background = StyleBoxFlat.new()
	background.bg_color = Color(0.04, 0.05, 0.12, 0.95)
	background.border_color = Color(0.0, 0.0, 0.0, 1.0)
	background.set_border_width_all(1)
	var fill = StyleBoxFlat.new()
	fill.bg_color = Color(0.15, 0.35, 1.0, 1.0)
	mana_bar.add_theme_stylebox_override("background", background)
	mana_bar.add_theme_stylebox_override("fill", fill)
	mana_bar.show()

func _get_health_color(object) -> Color:
	if "hp" in object and "max_hp" in object and object.max_hp > 0:
		var hp_pct = float(object.hp) / float(object.max_hp)
		return Color.RED.lerp(Color.GREEN, clamp(hp_pct, 0.0, 1.0))
	return Color.WHITE

func _set_standard_info_visible(should_show: bool):
	if unit_icon:
		unit_icon.visible = should_show
	if unit_name_label:
		unit_name_label.visible = should_show
	if kill_count_label:
		kill_count_label.visible = should_show
	if upgrade_label:
		upgrade_label.visible = should_show

func _set_text_labels_visible(should_show: bool):
	if unit_name_label:
		unit_name_label.visible = should_show
	if kill_count_label:
		kill_count_label.visible = should_show
	if upgrade_label:
		upgrade_label.visible = should_show

func _show_detail_text(text: String):
	if detail_text_label:
		detail_text_label.show()
		detail_text_label.text = text

func _hide_detail_text():
	if detail_text_label:
		detail_text_label.hide()

func _create_upgrade_tooltip():
	upgrade_tooltip_layer = CanvasLayer.new()
	upgrade_tooltip_layer.name = "UpgradeTooltipLayer"
	upgrade_tooltip_layer.layer = 128
	upgrade_tooltip_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(upgrade_tooltip_layer)

	upgrade_tooltip_panel = PanelContainer.new()
	upgrade_tooltip_panel.visible = false
	upgrade_tooltip_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.02, 0.02, 0.02, 0.96)
	panel_style.border_color = Color(0.55, 0.55, 0.55, 1.0)
	panel_style.set_border_width_all(1)
	panel_style.set_content_margin_all(8)
	upgrade_tooltip_panel.add_theme_stylebox_override("panel", panel_style)
	upgrade_tooltip_layer.add_child(upgrade_tooltip_panel)

	upgrade_tooltip_label = RichTextLabel.new()
	upgrade_tooltip_label.bbcode_enabled = true
	upgrade_tooltip_label.fit_content = true
	upgrade_tooltip_label.scroll_active = false
	upgrade_tooltip_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	upgrade_tooltip_label.custom_minimum_size = Vector2(180, 0)
	upgrade_tooltip_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	upgrade_tooltip_panel.add_child(upgrade_tooltip_label)

func _update_upgrade_tooltip():
	if not upgrade_tooltip_panel or not upgrade_tooltip_label:
		return
	var hovered_icon := _find_hovered_upgrade_icon()
	if hovered_icon and hovered_icon.has_meta("tooltip"):
		_show_upgrade_tooltip(hovered_icon, str(hovered_icon.get_meta("tooltip")), get_global_mouse_position())
	else:
		_hide_upgrade_tooltip()

func _find_hovered_upgrade_icon() -> Control:
	var mouse_pos := get_global_mouse_position()
	for icon in upgrade_icons:
		if icon is Control and icon.visible and icon.has_meta("tooltip") and icon.get_global_rect().has_point(mouse_pos):
			return icon
	return null

func _show_upgrade_tooltip(owner: Control, text: String, mouse_pos: Vector2):
	if text.is_empty():
		_hide_upgrade_tooltip()
		return
	if upgrade_tooltip_owner != owner or upgrade_tooltip_text_cache != text:
		upgrade_tooltip_owner = owner
		upgrade_tooltip_text_cache = text
		upgrade_tooltip_label.clear()
		upgrade_tooltip_label.parse_bbcode(text)
		upgrade_tooltip_panel.reset_size()
	var desired_size = upgrade_tooltip_panel.get_combined_minimum_size()
	var viewport_size = get_viewport_rect().size
	var next_pos = mouse_pos + UPGRADE_TOOLTIP_MARGIN
	if next_pos.x + desired_size.x > viewport_size.x:
		next_pos.x = mouse_pos.x - desired_size.x - UPGRADE_TOOLTIP_MARGIN.x
	if next_pos.y + desired_size.y > viewport_size.y:
		next_pos.y = mouse_pos.y - desired_size.y - UPGRADE_TOOLTIP_MARGIN.y
	next_pos.x = clamp(next_pos.x, 0.0, max(0.0, viewport_size.x - desired_size.x))
	next_pos.y = clamp(next_pos.y, 0.0, max(0.0, viewport_size.y - desired_size.y))
	upgrade_tooltip_panel.position = next_pos
	upgrade_tooltip_panel.visible = true

func _hide_upgrade_tooltip():
	upgrade_tooltip_owner = null
	upgrade_tooltip_text_cache = ""
	if upgrade_tooltip_panel:
		upgrade_tooltip_panel.visible = false

func _update_upgrade_icons(unit):
	if not upgrade_icon_row:
		return
	var manager = get_tree().get_first_node_in_group("UnitManager")
	var paths: Array = []
	var tips: Array = []
	if manager and manager.has_method("get_unit_upgrade_icon_paths"):
		paths = manager.get_unit_upgrade_icon_paths(unit)
	if manager and manager.has_method("get_unit_upgrade_tooltips"):
		tips = manager.get_unit_upgrade_tooltips(unit)
	if paths.is_empty():
		paths = ["res://icon/body0_upgrd.png", "res://icon/power0_upgrd.png"]
		if unit.is_in_group("Enemy"):
			tips = ["적 유닛 기본 체력", "적 유닛 기본 공격력"]
	if paths.is_empty():
		_hide_upgrade_icons()
		return
	upgrade_icon_row.show()
	for i in range(upgrade_icons.size()):
		var icon: TextureRect = upgrade_icons[i]
		if i < paths.size():
			icon.texture = load(str(paths[i]))
			icon.tooltip_text = ""
			icon.set_meta("tooltip", str(tips[i]) if i < tips.size() else "")
			icon.show()
		else:
			icon.texture = null
			icon.tooltip_text = ""
			if icon.has_meta("tooltip"):
				icon.remove_meta("tooltip")
			icon.hide()

func _hide_upgrade_icons():
	if upgrade_icon_row:
		upgrade_icon_row.hide()
	for icon in upgrade_icons:
		if icon:
			icon.hide()
			icon.tooltip_text = ""
			if icon.has_meta("tooltip"):
				icon.remove_meta("tooltip")
	_hide_upgrade_tooltip()

func _set_icon_layout(pos: Vector2, icon_size: Vector2):
	if not unit_icon:
		return
	unit_icon.position = pos
	unit_icon.custom_minimum_size = icon_size
	unit_icon.size = icon_size

func _hide_progress_bar():
	if progress_bar:
		progress_bar.hide()

func _hide_hp_ui():
	if hp_bar:
		hp_bar.hide()
	if hp_value_label:
		hp_value_label.hide()

func _hide_mana_bar():
	if mana_bar:
		mana_bar.hide()

func _hide_production_ui():
	if production_queue_view:
		production_queue_view.hide()
