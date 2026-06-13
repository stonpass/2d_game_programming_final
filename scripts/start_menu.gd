extends Control

# 게임 씬 경로 (본인의 게임 씬 파일 경로로 수정하세요)
@export var game_scene_path : String = "res://scenes/main/main_game.tscn"

@onready var start_button: Button = $CenterContainer/VBoxContainer/StartButton
@onready var exit_button: Button = $CenterContainer/VBoxContainer/ExitButton

func _ready():
	# 버튼 시그널 연결
	start_button.pressed.connect(_on_start_pressed)
	exit_button.pressed.connect(_on_exit_pressed)

func _on_start_pressed():
	get_tree().root.set_meta("test_mode", Input.is_key_pressed(KEY_SPACE))
	# 게임 씬으로 전환
	get_tree().change_scene_to_file(game_scene_path)

func _on_exit_pressed():
	# 게임 종료
	get_tree().quit()
