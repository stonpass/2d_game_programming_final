extends Control

@onready var bg = get_tree().current_scene.find_child("Background", true, false)
var viewport_size := Vector2(190, 190)
var border_offset := Vector2(12.5, 12.5)
var menu_height_px : float = 170.0 

func _process(_delta):
	queue_redraw()

func _draw():
	if not bg: return
	var main_cam = get_viewport().get_camera_2d()
	if not main_cam: return
	var manager = get_tree().get_first_node_in_group("UnitManager")

	var bg_rect = bg.get_rect()
	var bg_world_size = bg_rect.size * bg.global_scale
	var bg_start_pos = bg.global_position + (bg_rect.position * bg.global_scale)
	
	# [기존 잘 작동하던 로직 활용] 
	# 월드 좌표를 미니맵 내부 0~190 좌표로 변환 (clamp 포함)
	var to_map = func(world_pos: Vector2):
		var rel_x = world_pos.x - bg_start_pos.x
		var rel_y = world_pos.y - bg_start_pos.y
		var map_x = (rel_x / bg_world_size.x) * viewport_size.x
		var map_y = (rel_y / bg_world_size.y) * viewport_size.y
		# 좌표가 미니맵 밖으로 나가지 않도록 0~190 사이로 제한
		return Vector2(clamp(map_x, 0, viewport_size.x), clamp(map_y, 0, viewport_size.y))

	# 1. 카메라 박스 (네모 고정 및 상단 끝 도달 보정)
	var view_size = get_viewport_rect().size / main_cam.zoom
	
	# 시야의 각 끝 지점 계산
	var cam_left = main_cam.global_position.x - view_size.x/2.0
	var cam_top = main_cam.global_position.y - view_size.y/2.0
	var cam_right = main_cam.global_position.x + view_size.x/2.0
	# 하단은 메뉴바 높이만큼 뺀 '실제 보이는 끝'
	var cam_bottom = main_cam.global_position.y + (view_size.y/2.0) - menu_height_px

	# 미니맵 좌표로 변환 (to_map이 0~190으로 잡아줌)
	var m_top_left = to_map.call(Vector2(cam_left, cam_top))
	var m_bottom_right = to_map.call(Vector2(cam_right, cam_bottom))
	
	# [핵심 보정] 상자의 크기를 일정하게 유지하기 위한 로직
	# 카메라가 맵 중앙에 있을 때의 '정상적인 상자 크기'를 기준으로 잡음
	var fixed_w = (view_size.x / bg_world_size.x) * viewport_size.x
	var fixed_h = ((view_size.y - menu_height_px) / bg_world_size.y) * viewport_size.y
	
	# 시작점(m_top_left)을 기준으로 그리되, 
	# 카메라가 하단 끝에 도달했을 때 상자가 맵 바닥에 딱 붙도록 위치를 보정
	var final_rect_pos = m_top_left
	if m_bottom_right.y >= viewport_size.y:
		final_rect_pos.y = viewport_size.y - fixed_h
	if m_bottom_right.x >= viewport_size.x:
		final_rect_pos.x = viewport_size.x - fixed_w
	
	# 최종 드로잉 (border_offset 적용)
	var final_rect = Rect2(final_rect_pos + border_offset, Vector2(fixed_w, fixed_h))
	draw_rect(final_rect, Color.WHITE, false, 2.0)

	# 2. 유닛 점
	for unit in get_tree().get_nodes_in_group("Unit"):
		if not is_instance_valid(unit) or not (unit is Node2D):
			continue
		var dot_pos = to_map.call(unit.global_position) + border_offset
		if Rect2(border_offset, viewport_size).has_point(dot_pos):
			var dot_color = Color.RED if unit.is_in_group("Enemy") else Color.GREEN
			if unit.is_in_group("Ally") and manager and manager.has_method("get_minimap_ally_attack_color"):
				dot_color = manager.get_minimap_ally_attack_color(unit)
			draw_circle(dot_pos, 2.5, dot_color)

	# 3. 아군 건물 네모
	for resource in get_tree().get_nodes_in_group("ResourceDeposit"):
		if not is_instance_valid(resource) or not (resource is Node2D) or resource.is_in_group("Building"):
			continue
		var resource_pos = to_map.call(resource.global_position) + border_offset
		if Rect2(border_offset, viewport_size).has_point(resource_pos):
			draw_circle(resource_pos, 2.2, Color(0.45, 0.9, 1.0, 1.0))

	for building in get_tree().get_nodes_in_group("Building"):
		if not is_instance_valid(building) or not (building is Node2D):
			continue
		var building_pos = to_map.call(building.global_position) + border_offset
		if Rect2(border_offset, viewport_size).has_point(building_pos):
			var marker_size := Vector2(6, 6)
			if building.has_method("get_rect"):
				var rect: Rect2 = building.get_rect()
				var a = to_map.call(rect.position) + border_offset
				var b = to_map.call(rect.position + rect.size) + border_offset
				marker_size = (b - a).abs()
				marker_size.x = clamp(marker_size.x, 4.0, 18.0)
				marker_size.y = clamp(marker_size.y, 4.0, 18.0)
			var marker_color = Color.RED if building.is_in_group("Enemy") else Color.GREEN
			if building.is_in_group("Ally") and manager and manager.has_method("get_minimap_ally_attack_color"):
				marker_color = manager.get_minimap_ally_attack_color(building)
			draw_rect(Rect2(building_pos - marker_size * 0.5, marker_size), marker_color, true)
