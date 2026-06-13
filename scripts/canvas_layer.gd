extends Node2D


func _ready():
	# 처음에는 메뉴를 숨김
	visible = false
	$CenterContainer/VBoxContainer/ResumeButton.pressed.connect(_on_resume_pressed)
	$CenterContainer/VBoxContainer/QuitButton.pressed.connect(_on_quit_pressed)

func _input(event):
	if event.is_action_pressed("ui_cancel"): # 기본적으로 ESC 키가 할당되어 있음
		if not _can_pause_from_escape():
			return
		toggle_pause()

func _can_pause_from_escape() -> bool:
	var manager = get_tree().get_first_node_in_group("UnitManager")
	if manager and "unit_selected" in manager and not manager.unit_selected.is_empty():
		return false
	return true

func toggle_pause():
	# 일시정지 상태 반전
	var new_pause_state = !get_tree().paused
	get_tree().paused = new_pause_state
	visible = new_pause_state # 메뉴 보이기/숨기기

func _on_resume_pressed():
	toggle_pause() # 게임 재개

func _on_quit_pressed():
	get_tree().paused = false # 종료 전 일시정지 해제 (매너)
	get_tree().quit()
