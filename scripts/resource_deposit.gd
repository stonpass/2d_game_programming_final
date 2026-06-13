extends Area2D

@export var resource_amount: int = 1500
@export var max_resource_amount: int = 0
@export var click_size: Vector2 = Vector2(72, 52)
@export var footprint_tiles: Vector2i = Vector2i(5, 4)
@export var display_name: String = "청금석덩어리"
@export var description: String = "청금석덩어리다 [color=#ffd84a]학생[/color]으로 청금석을 채취할 수 있다"
@export var icon_texture: Texture2D = preload("res://캐릭터 폴더/map/blue.png")

const SELECTION_RING_SCRIPT = preload("res://scripts/selection_ring.gd")
const DEPTH_SORT_OFFSET := 2048

var hover_mode: bool = false
var select_mode: bool = false
var selection_ring

func _ready():
	add_to_group("ResourceDeposit")
	if max_resource_amount <= 0:
		max_resource_amount = resource_amount
	input_pickable = true
	z_index = clampi(int(global_position.y) + DEPTH_SORT_OFFSET, 0, 4096)
	_create_selection_ring()
	queue_redraw()

func get_footprint_tiles() -> Vector2i:
	return footprint_tiles

func take_resource(amount: int) -> int:
	if resource_amount <= 0:
		return 0
	var mined = min(amount, resource_amount)
	resource_amount -= mined
	if resource_amount <= 0:
		_clear_selection_if_selected()
		_clear_placement_obstacle()
		queue_free()
	else:
		queue_redraw()
		_refresh_selection_info_if_selected()
	return mined

func play_gather_effect(_gatherer_position: Vector2 = Vector2.ZERO):
	var particles = _create_gather_particles()
	add_child(particles)
	particles.restart()
	particles.emitting = true
	var timer = get_tree().create_timer(particles.lifetime + 0.2)
	timer.timeout.connect(Callable(self, "_free_gather_particles").bind(particles.get_instance_id()))

func _free_gather_particles(particles_id: int):
	var particles = instance_from_id(particles_id)
	if particles and is_instance_valid(particles):
		particles.queue_free()

func is_depleted() -> bool:
	return resource_amount <= 0

func get_max_resource_amount() -> int:
	return max_resource_amount

func _clear_placement_obstacle():
	var placement = get_tree().get_first_node_in_group("BuildingPlacement")
	if placement and placement.has_method("clear_node_obstacle"):
		placement.clear_node_obstacle(self)

func get_rect() -> Rect2:
	return Rect2(global_position - click_size * 0.5, click_size)

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

func _clear_selection_if_selected():
	if not select_mode:
		return
	var manager = get_tree().get_first_node_in_group("UnitManager")
	if manager and manager.has_method("_clear_selection"):
		manager._clear_selection()

func _create_selection_ring():
	selection_ring = Node2D.new()
	selection_ring.set_script(SELECTION_RING_SCRIPT)
	var visual_size = _get_visual_size()
	selection_ring.radius = min(visual_size.x, visual_size.y) * 0.27
	selection_ring.ellipse_scale = Vector2(1.1, 0.4)
	selection_ring.offset = Vector2(0, 7)
	selection_ring.hover_color = Color(1.0, 0.95, 0.0, 1.0)
	selection_ring.selected_color = Color(1.0, 0.95, 0.0, 1.0)
	selection_ring.visible = false
	add_child(selection_ring)

func _create_gather_particles() -> CPUParticles2D:
	var particles = CPUParticles2D.new()
	particles.name = "GatherParticles"
	particles.position = Vector2(0, -22)
	particles.amount = 18
	particles.lifetime = 0.55
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.randomness = 0.65
	particles.emitting = false
	particles.local_coords = true
	particles.direction = Vector2(0, -1)
	particles.spread = 180.0
	particles.gravity = Vector2(0, 45)
	particles.initial_velocity_min = 18.0
	particles.initial_velocity_max = 58.0
	particles.scale_amount_min = 2.0
	particles.scale_amount_max = 4.0
	particles.color = Color(0.45, 0.9, 1.0, 0.95)
	particles.z_index = 10
	return particles

func _get_visual_size() -> Vector2:
	var sprite = get_node_or_null("Sprite2D")
	if sprite and sprite is Sprite2D and sprite.texture:
		return sprite.texture.get_size() * sprite.scale
	return click_size

func _update_selection_ring():
	if selection_ring:
		selection_ring.set_modes(hover_mode, select_mode)

func _draw():
	var ratio = clamp(float(resource_amount) / 1500.0, 0.0, 1.0)
	if not has_node("Sprite2D"):
		var body_color = Color(0.25, 0.75, 0.95).lerp(Color(0.1, 0.32, 0.45), 1.0 - ratio)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.6, 1.0))
		draw_circle(Vector2.ZERO, 23.0, body_color)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		draw_arc(Vector2.ZERO, 37.0, 0.0, TAU, 32, Color(0.75, 0.95, 1.0, 0.85), 2.0)
