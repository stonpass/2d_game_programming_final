extends Node2D

@export var radius: float = 32.0
@export var offset: Vector2 = Vector2.ZERO
@export var ellipse_scale: Vector2 = Vector2(1.0, 0.5)
@export var hover_color: Color = Color(1.0, 0.95, 0.0, 1.0)
@export var selected_color: Color = Color(0.0, 1.0, 0.0, 0.9)
@export var line_width: float = 4.5

var hover_mode: bool = false
var select_mode: bool = false

func _ready():
	z_as_relative = true
	z_index = -10

func set_modes(is_hover: bool, is_selected: bool):
	if hover_mode == is_hover and select_mode == is_selected:
		return
	hover_mode = is_hover
	select_mode = is_selected
	visible = hover_mode or select_mode
	queue_redraw()

func _draw():
	if not hover_mode and not select_mode:
		return
	var color = selected_color if select_mode else hover_color
	draw_set_transform(offset, 0.0, ellipse_scale)
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 48, color, line_width, true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
