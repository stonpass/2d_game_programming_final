extends AudioStreamPlayer

const TRACKS: Array[AudioStream] = [
	preload("res://assets/muic/Starcraft Terran Theme 2 - TiMeX.mp3"),
	preload("res://assets/muic/StarCraft - Terran Theme 1 - Katrulzin.mp3"),
	preload("res://assets/muic/Starcraft Terran Theme 3 - TiMeX.mp3")
]
const NEXT_TRACK_DELAY := 10.0
const MUSIC_VOLUME_RATIO := 0.5

var track_index := 0

func _ready():
	volume_db = linear_to_db(MUSIC_VOLUME_RATIO)
	finished.connect(_on_finished)
	_play_current_track()

func _play_current_track():
	if TRACKS.is_empty():
		return
	stream = TRACKS[track_index]
	play()

func _on_finished():
	await get_tree().create_timer(NEXT_TRACK_DELAY).timeout
	track_index = (track_index + 1) % TRACKS.size()
	_play_current_track()
