extends Control
## Tela de seleção de personagens.
## A barra superior (10 slots) faz parte da ARTE do fundo — aqui cada
## espaço dela vira um slot REAL do jogo: uma área de clique invisível
## em cima da arte, ligada ao Roster (scripts/roster.gd). O 1º slot tem
## o Seu Madruga; os outros são cadeados mas já guardam um espaço de
## verdade pra um futuro personagem. Nada visual é adicionado: a arte
## da barra continua exatamente como estava.
## Ao iniciar a luta, o modelo escolhido é o que o jogo carrega.

const BG_IMAGE := "res://characterselection/a4d41d61-0ea4-4bcc-8961-09f1c2657eb5.png"
const SELECT_MUSIC := "res://characterselection/dbz-saga-buu-soundtrack-9_XlACdWDP.wav"
const GAME_SCENE := "res://scenes/main.tscn"
## Fallback da barra (px) caso o personagem não tenha bar_rect medido.
const BAR_ART := Rect2(27.0, 26.0, 799.0, 97.0)

var _music: AudioStreamPlayer
var _select_button: Button
var _bg_rect: TextureRect
var _bg_tex: Texture2D
var _slots_layer: Control
var _slot_buttons: Array[Button] = []


func _ready() -> void:
	# Garante que este Control ocupe a tela toda (caso o .tscn nao tenha anchors).
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_background()
	_build_overlay()
	_build_slots()
	_build_menu()
	_build_music()


func _build_background() -> void:
	var bg := TextureRect.new()
	bg.name = "Background"
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	# KEEP (não COVERED): as artes são retrato, COVERED corta o topo
	# (os slots). KEEP mostra a arte inteira centralizada.
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var tex := _selected_art()
	if tex == null:
		push_warning("Imagem de fundo nao encontrada")
	else:
		bg.texture = tex
		_bg_tex = tex
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg_rect = bg
	add_child(bg)
	move_child(bg, 0)


## Arte da tela de seleção do personagem atualmente escolhido: cada
## personagem tem a arte INTEIRA da tela (barra com o retrato destacado
## e a plaquinha do nome já desenhadas nela).
func _selected_art() -> Texture2D:
	var c := Roster.get_selected()
	if c != null and c.select_image != "":
		var t := load(c.select_image) as Texture2D
		if t != null:
			return t
		push_warning("Arte de seleção nao encontrada: %s" % c.select_image)
	return load(BG_IMAGE) as Texture2D


## Troca a arte da tela pra mostrar o personagem escolhido. As artes
## têm resoluções diferentes mas a mesma proporção e layout de barra,
## então os slots invisíveis continuam alinhados (e o _layout_slots()
## garante o re-encaixe mesmo que uma arte mude de tamanho).
func _apply_selected_art() -> void:
	var tex := _selected_art()
	if tex == null or _bg_rect == null:
		return
	_bg_tex = tex
	_bg_rect.texture = tex
	_layout_slots()


func _build_overlay() -> void:
	# Escurece um pouco o fundo pra dar leitura ao botão.
	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.0, 0.0, 0.0, 0.35)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)


## Cria os slots REAIS da barra: um botão invisível por espaço da arte,
## posicionado em cima do desenho do slot por _layout_slots.
func _build_slots() -> void:
	_slots_layer = Control.new()
	_slots_layer.name = "Slots"
	_slots_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_slots_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_slots_layer)

	for i in Roster.SLOT_COUNT:
		var slot := Button.new()
		slot.name = "Slot%d" % i
		slot.flat = true
		slot.focus_mode = Control.FOCUS_NONE
		# invisível de verdade: sem estilo e sem texto (nada muda na tela)
		for state in ["normal", "hover", "pressed", "disabled", "focus"]:
			slot.add_theme_stylebox_override(state, StyleBoxEmpty.new())
		# só o cursor muda: mão no slot livre, "proibido" no cadeado
		slot.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if Roster.is_selectable(i) else Control.CURSOR_FORBIDDEN
		slot.pressed.connect(_on_slot_pressed.bind(i))
		_slots_layer.add_child(slot)
		_slot_buttons.append(slot)
	_slots_layer.resized.connect(_layout_slots)
	_layout_slots()
	call_deferred("_layout_slots")


## Encaixa os botões invisíveis exatamente sobre os slots desenhados na
## arte (ela usa KEEP_ASPECT_CENTERED, então o encaixe muda com a janela).
func _layout_slots() -> void:
	if _slots_layer == null or _bg_tex == null:
		return
	var tex_size := _bg_tex.get_size()
	if tex_size.x <= 0.0 or tex_size.y <= 0.0:
		return
	var fit := minf(_slots_layer.size.x / tex_size.x, _slots_layer.size.y / tex_size.y)
	var drawn := tex_size * fit
	var origin := (_slots_layer.size - drawn) * 0.5
	# a barra medida vai na arte do personagem SELECIONADO: cada arte tem
	# sua posição de barra (a IA regenera cada uma levemente diferente),
	# então o encaixe é recalculado a cada troca de personagem.
	var bar := BAR_ART
	var c := Roster.get_selected()
	if c != null and c.bar_rect.size.x > 0.0:
		bar = c.bar_rect
	var slot_w := bar.size.x / float(_slot_buttons.size())
	for i in _slot_buttons.size():
		var art := Rect2(bar.position.x + slot_w * float(i), bar.position.y, slot_w, bar.size.y)
		var b := _slot_buttons[i]
		b.position = origin + art.position * fit
		b.size = art.size * fit


func _on_slot_pressed(i: int) -> void:
	if Roster.select_slot(i):
		# escolha guardada no Roster — é ela que a luta vai importar
		_apply_selected_art()
		return
	# cadeado: o espaço é real (slot existe no Roster), só falta o personagem
	print("Slot %d bloqueado — espaço reservado pra um personagem futuro." % i)


func _build_menu() -> void:
	# Botão ancorado na parte de baixo, centralizado.
	var bottom := CenterContainer.new()
	bottom.name = "Bottom"
	bottom.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_top = -190.0
	bottom.offset_bottom = -40.0
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bottom)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom.add_child(box)

	_select_button = Button.new()
	_select_button.name = "SelectButton"
	_select_button.text = "SELECIONAR PERSONAGEM"
	_select_button.custom_minimum_size = Vector2(560.0, 90.0)
	_select_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_select_button.add_theme_font_size_override("font_size", 36)
	_select_button.focus_mode = Control.FOCUS_ALL
	_select_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_select_button.pressed.connect(_on_select_pressed)
	box.add_child(_select_button)

	var hint := Label.new()
	hint.text = "Clique num retrato da barra pra escolher · ENTER pra lutar!"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 20)
	hint.modulate = Color(1, 1, 1, 0.8)
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(hint)

	# Foco inicial: ja permite dar ENTER direto.
	_select_button.grab_focus()


func _build_music() -> void:
	# Trilha da tela de seleção: toca COMPLETA e só então reinicia.
	# (LOOP_FORWARD com loop_end calculado em frames cortava a música no
	# meio, então usamos LOOP_NONE + sinal finished pra recomeçar.)
	_music = AudioStreamPlayer.new()
	_music.name = "SelectMusic"
	var stream := load(SELECT_MUSIC) as AudioStreamWAV
	if stream == null:
		# Tenta como AudioStream generico (caso o import mude o tipo).
		var generic := load(SELECT_MUSIC) as AudioStream
		if generic == null:
			push_warning("Musica nao encontrada: %s" % SELECT_MUSIC)
			return
		_music.stream = generic
	else:
		stream.loop_mode = AudioStreamWAV.LOOP_DISABLED
		_music.stream = stream
	_music.volume_db = -7.0
	add_child(_music)
	_music.finished.connect(_on_music_finished)
	_music.play()


func _on_music_finished() -> void:
	# Recomeça do zero só quando a música termina de verdade.
	if _music != null:
		_music.play()


func _unhandled_input(event: InputEvent) -> void:
	# ENTER / ESPACO tambem iniciam a luta.
	if event.is_action_pressed("ui_accept"):
		_on_select_pressed()
		get_viewport().set_input_as_handled()


func _on_select_pressed() -> void:
	# Sai da seleção e vai para a luta de fato.
	get_tree().change_scene_to_file(GAME_SCENE)
