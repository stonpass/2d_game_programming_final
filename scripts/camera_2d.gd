extends Camera2D

@export var start_position: Vector2 = Vector2(-1110, 585)
@export var custom_zoom: float = 0.8
@export var speed: float = 1200.0
@export var margin: float = 20.0
var menu_height: float = 170.0 

func _ready():
	global_position = start_position
	zoom = Vector2(custom_zoom, custom_zoom)
	make_current()
	call_deferred("_setup_camera_limits")

func _setup_camera_limits():
	var bg = get_tree().current_scene.find_child("Background", true, false)
	if bg:
		var rect = bg.get_rect()
		var s = bg.global_scale
		
		limit_left = bg.global_position.x + (rect.position.x * s.x)
		limit_top = bg.global_position.y + (rect.position.y * s.y)
		limit_right = limit_left + (rect.size.x * s.x)
		# [요청 반영] 배경 끝보다 170픽셀 더 아래까지 이동 가능하도록 설정
		limit_bottom = (bg.global_position.y + (rect.end.y * s.y)) + menu_height
	global_position = start_position

func _process(delta):
	var move_vec = Vector2.ZERO
	var mouse_pos = get_viewport().get_mouse_position()
	var screen_size = get_viewport().get_visible_rect().size

	if mouse_pos.x < margin: move_vec.x = -1
	elif mouse_pos.x > screen_size.x - margin: move_vec.x = 1
	if mouse_pos.y < margin: move_vec.y = -1
	elif mouse_pos.y > screen_size.y - margin: move_vec.y = 1

	if move_vec != Vector2.ZERO:
		var view_size = get_viewport_rect().size / zoom
		var half_view = view_size / 2.0
		var next_pos = global_position + move_vec.normalized() * speed * delta
		
		# 제한 범위 내에서 이동 (limit_bottom이 확장되었으므로 더 아래로 내려감)
		next_pos.x = clamp(next_pos.x, limit_left + half_view.x, limit_right - half_view.x)
		next_pos.y = clamp(next_pos.y, limit_top + half_view.y, limit_bottom - half_view.y)
		
		global_position = next_pos
