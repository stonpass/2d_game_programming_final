extends Panel

@onready var sub_viewport = $SubViewportContainer/SubViewport
@onready var mini_camera = $SubViewportContainer/SubViewport/MiniMapCamera
@onready var bg = get_tree().current_scene.find_child("Background", true, false)

var is_dragging = false
var menu_height_px : float = 170.0
var viewport_size := Vector2(190, 190) # 가로세로 10씩 줄인 크기
var border_offset := Vector2(12.5, 12.5) # 중앙 정렬용 오프셋

func _ready():
	await get_tree().process_frame
	# 메인 화면의 월드를 미니맵에 연결
	sub_viewport.world_2d = get_viewport().world_2d
	
	if bg:
		var bg_rect = bg.get_rect()
		var world_size = bg_rect.size * bg.global_scale
		# 190px 뷰포트에 맞게 미니맵 자체 카메라 줌 설정
		var ratio = viewport_size.x / world_size.x
		mini_camera.zoom = Vector2(ratio, ratio)
		mini_camera.global_position = bg.global_position + (bg_rect.get_center() * bg.global_scale)

# [복구] 마우스 입력 감지 함수
func _gui_input(event):
	# 왼쪽 마우스 버튼 클릭 시
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			is_dragging = event.pressed
			if is_dragging:
				move_main_camera(event.position)
	
	# 마우스 드래그 시
	if event is InputEventMouseMotion and is_dragging:
		move_main_camera(event.position)

# [복구] 메인 카메라 이동 로직
func move_main_camera(click_pos: Vector2):
	if not bg: return
	
	# 1. 패널 내 실제 뷰포트 영역(190x190) 안의 좌표로 보정
	var local_click = click_pos - border_offset
	
	# 2. 0.0 ~ 1.0 비율 계산 (190 기준)
	var pct_x = clamp(local_click.x / viewport_size.x, 0.0, 1.0)
	var pct_y = clamp(local_click.y / viewport_size.y, 0.0, 1.0)
	
	# 3. 월드 좌표 역산
	var bg_rect = bg.get_rect()
	var bg_world_pos = bg.global_position + (bg_rect.position * bg.global_scale)
	var bg_world_size = bg_rect.size * bg.global_scale
	
	# 씬의 전체 논리적 높이 (지형 + 메뉴바 170)
	var total_logic_height = bg_world_size.y + menu_height_px
	
	var target_x = bg_world_pos.x + (pct_x * bg_world_size.x)
	var target_y = bg_world_pos.y + (pct_y * total_logic_height)
	
	# 4. 메인 카메라 찾아서 즉시 이동
	var main_cam = get_viewport().get_camera_2d()
	if main_cam:
		main_cam.global_position = Vector2(target_x, target_y)
