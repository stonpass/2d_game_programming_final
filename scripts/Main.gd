extends Control

var dragging = false
var start_pos = Vector2.ZERO
var current_rect = Rect2()

# 월드에 있는 매니저를 참조 (경로 주의)
@onready var manager = get_node("../../World/UnitManager")

func _input(event):
	# 1. 우클릭: 유닛 이동 (월드 좌표 필요)
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		if manager:
			manager.move_to_position(get_global_mouse_position())

	# 2. 좌클릭: 드래그 시작/종료
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		# 하단 UI 영역(BottomPanel)을 클릭했을 때는 드래그 무시 로직을 넣을 수 있음
		if event.pressed:
			dragging = true
			start_pos = get_local_mouse_position()
		else:
			dragging = false
			if manager:
				manager.check_unit()
			queue_redraw()

	# 3. 마우스 이동: 박스 갱신
	if event is InputEventMouseMotion and dragging:
		current_rect = Rect2(start_pos, get_local_mouse_position() - start_pos).abs()
		
		# [중요] 판정용 Rect는 월드 좌표(Global)로 변환해서 매니저에게 전달
		if manager:
			var g_start = get_global_mouse_position() - (get_local_mouse_position() - start_pos)
			var g_current = get_global_mouse_position()
			manager.selected_rect = Rect2(g_start, g_current - g_start).abs()
		
		queue_redraw()

func _draw():
	if dragging:
		# 내부 반투명 (비쳐 보임)
		draw_rect(current_rect, Color(0, 1, 0, 0.15), true)
		# 테두리 (깔끔한 선)
		draw_rect(current_rect, Color(0, 1, 0, 0.5), false, 1.0)
