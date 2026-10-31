extends Control
## Tela de titulo: mostra a imagem de fundo, toca o tema do Guile em loop
## e tem o botao PLAY que leva para a seleção de personagens
## (scenes/select.tscn).

const BG_IMAGE := "res://watermarked_img_15797068510704090238.png"
const TITLE_MUSIC := "res://guile_theme.wav"
const SELECT_SCENE := "res://scenes/select.tscn"

var _music: AudioStreamPlayer
var _play_button: Button


func _ready() -> void:
	# Garante que este Control ocupe a tela toda (caso o .tscn nao tenha anchors).
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_background()
	_build_overlay()
	_build_menu()
	_build_music()


func _build_background() -> void:
	var bg := TextureRect.new()
	bg.name = "Background"
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	var tex := load(BG_IMAGE) as Texture2D
	if tex == null:
		push_warning("Imagem de fundo nao encontrada: %s" % BG_IMAGE)
	else:
		bg.texture = tex
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	move_child(bg, 0)


func _build_overlay() -> void:
	# Escurece um pouco o fundo pra dar leitura ao titulo e ao PLAY.
	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.0, 0.0, 0.0, 0.45)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)


func _build_menu() -> void:
	var center := CenterContainer.new()
	center.name = "Center"
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 28)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(box)

	_play_button = Button.new()
	_play_button.name = "PlayButton"
	_play_button.text = "PLAY"
	_play_button.custom_minimum_size = Vector2(340.0, 96.0)
	_play_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_play_button.add_theme_font_size_override("font_size", 52)
	_play_button.focus_mode = Control.FOCUS_ALL
	_play_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_play_button.pressed.connect(_on_play_pressed)
	box.add_child(_play_button)

	var hint := Label.new()
	hint.text = "Clique em PLAY ou aperte ENTER"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 20)
	hint.modulate = Color(1, 1, 1, 0.8)
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(hint)

	# Foco inicial: ja permite dar ENTER direto.
	_play_button.grab_focus()


func _build_music() -> void:
	# Trilha da tela de titulo em looping eterno. Quando acaba, reinicia.
	_music = AudioStreamPlayer.new()
	_music.name = "TitleMusic"
	var stream := load(TITLE_MUSIC) as AudioStreamWAV
	if stream == null:
		# Tenta como AudioStream generico (caso o import mude o tipo).
		var generic := load(TITLE_MUSIC) as AudioStream
		if generic == null:
			push_warning("Musica nao encontrada: %s" % TITLE_MUSIC)
			return
		_music.stream = generic
	else:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		# loop_end em frames de sample: data tem 2ch * 16bit, logo frames = bytes / 4.
		var total_frames := int(stream.data.size() / 4)
		stream.loop_begin = 0
		stream.loop_end = total_frames
		_music.stream = stream
	_music.volume_db = -7.0
	add_child(_music)
	_music.play()


func _unhandled_input(event: InputEvent) -> void:
	# ENTER / ESPACO tambem iniciam o jogo.
	if event.is_action_pressed("ui_accept"):
		_on_play_pressed()
		get_viewport().set_input_as_handled()


func _on_play_pressed() -> void:
	# Sai da tela de titulo e vai para a seleção de personagens.
	get_tree().change_scene_to_file(SELECT_SCENE)
