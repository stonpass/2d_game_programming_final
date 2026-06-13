extends Control

var dragging = false
var start_pos = Vector2.ZERO
var current_rect = Rect2()
const DRAG_SELECT_THRESHOLD := 8.0

func _get_manager():
	var manager = get_tree().get_first_node_in_group("UnitManager")
	if manager == null:
		print("경고: UnitManager 그룹을 찾을 수 없습니다! 노드 설정을 확인하세요.")
	return manager

func _get_camera():
	return get_viewport().get_camera_2d()

func _draw():
	if dragging:
		# 드래그 박스 시각화 (반투명 녹색)
		draw_rect(current_rect, Color(0, 1, 0, 0.15), true)
		draw_rect(current_rect, Color(0, 1, 0, 0.6), false, 1.5)

func _input(event):
	var cam = _get_camera()
	var manager = _get_manager()
	
	if not cam or not manager: return

	# ----- [픽셀 단위 비대칭 하단 UI 정밀 방어벽] -----
	if event is InputEventMouseButton and event.pressed:
		var W = get_viewport_rect().size.x # 화면 전체 가로 크기
		var H = get_viewport_rect().size.y # 화면 전체 세로 크기
		var mouse_x = event.position.x
		var mouse_y = event.position.y
		
		# 1. 좌측 미니맵 구역 (가로 0px ~ 215px)
		if mouse_x >= 0 and mouse_x <= 215:
			if mouse_y >= H - 215: 
				return # 클릭 무시 (차단)
				
		# 2. 우측 버튼창 구역 (가로 화면끝-215px ~ 화면끝)
		elif mouse_x >= W - 215 and mouse_x <= W:
			if mouse_y >= H - 215: 
				return # 클릭 무시 (차단)
				
		# 3. 중앙 정보창 구역 (가로 215px ~ 화면끝-215px)
		else:
			if mouse_y >= H - 170: 
				return # 클릭 무시 (차단)
			# ※ 이 조건문 덕분에 (H - 215)와 (H - 170) 사이의 45픽셀 높이 빈 공간은 
			# return을 만나지 않고 통과하므로 아래에서 정상적으로 땅 클릭/이동/드래그가 작동합니다!

	# ----------------------------------------------------------------------
	# 1. 우클릭 이동
	# ----------------------------------------------------------------------
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		if event.pressed:
			var global_mouse_pos = cam.get_canvas_transform().affine_inverse() * event.position
			manager.move_to_position(global_mouse_pos)
			
			dragging = false 
			queue_redraw()

	# ----------------------------------------------------------------------
	# 2. 좌클릭 드래그 및 선택 시작
	# ----------------------------------------------------------------------
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			dragging = true
			start_pos = event.position
			_update_manager_rect(cam, manager, event.position)
		else:
			if dragging:
				var was_drag_select = start_pos.distance_to(event.position) >= DRAG_SELECT_THRESHOLD
				dragging = false
				if was_drag_select:
					manager.check_unit()
				queue_redraw()

	# ----------------------------------------------------------------------
	# 3. 드래그 중 마우스 이동
	# ----------------------------------------------------------------------
	if event is InputEventMouseMotion and dragging:
		_update_manager_rect(cam, manager, event.position)
		queue_redraw()

# 드래그/클릭 영역을 월드 좌표로 변환하여 Manager에 전달하는 함수
func _update_manager_rect(cam, manager, current_mouse_pos):
	# 화면에 그려질 사각형 (캔버스 좌표)
	current_rect = Rect2(start_pos, current_mouse_pos - start_pos).abs()
	
	# 실제 월드 좌표로 변환
	var inv_trans = cam.get_canvas_transform().affine_inverse()
	var world_start = inv_trans * start_pos
	var world_end = inv_trans * current_mouse_pos
	
	var final_rect = Rect2(world_start, world_end - world_start).abs()
	
	# [핵심] 만약 크기가 너무 작으면(단순 클릭) 최소 4x4 픽셀 영역으로 확장
	if final_rect.size.x < 2 or final_rect.size.y < 2:
		final_rect = Rect2(world_start - Vector2(2, 2), Vector2(4, 4))
		
	manager.selected_rect = final_rect
