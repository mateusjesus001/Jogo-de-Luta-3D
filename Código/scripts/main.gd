extends Node3D
## Cena principal: monta arena, câmera, lutadores, HUD e controla os rounds
## (melhor de 3). Tudo é criado por código, sem assets externos.

enum Phase { INTRO, FIGHT, ROUND_END, MATCH_END }

const ROUNDS_TO_WIN := 2
const ROUND_TIME := 60
const START_X := 2.0
const MUSIC_STREAM := "res://DBZ_Saga_Buu_Soundtrack_40_V1.ogg"
## Tela de seleção de personagens (T durante a luta volta pra ela).
const SELECT_SCENE := "res://scenes/select.tscn"
## texturas do cenário (scenariotextures/)
const WALL_TEX := "res://scenariotextures/wall.png"
const PILLAR_TEX := "res://scenariotextures/pilar.png"
const CRATE_TEX := "res://scenariotextures/box.png"

@export var p2_is_ai := true   # false = dois jogadores no mesmo teclado

var p1: Fighter
var p2: Fighter
var cam: Camera3D
var music: AudioStreamPlayer
var phase: Phase = Phase.INTRO
var phase_frames := 0
var round_no := 1
var wins: Array[int] = [0, 0]
var time_left := float(ROUND_TIME)

var bar1: ProgressBar
var bar2: ProgressBar
var timer_label: Label
var msg_label: Label


func _ready() -> void:
	_setup_inputs()
	_build_world()
	_build_audio()
	_build_fighters()
	_build_hud()
	_start_round()


# ---------------------------------------------------------------- SETUP

func _setup_inputs() -> void:
	var map := {
		"p1_left": KEY_A, "p1_right": KEY_D, "p1_up": KEY_W, "p1_down": KEY_S,
		"p1_punch": KEY_J, "p1_heavy": KEY_K, "p1_kick": KEY_L, "p1_special": KEY_SPACE,
		"p2_left": KEY_LEFT, "p2_right": KEY_RIGHT, "p2_up": KEY_UP, "p2_down": KEY_DOWN,
		"p2_punch": KEY_COMMA, "p2_heavy": KEY_PERIOD, "p2_kick": KEY_SLASH,
		"back_to_select": KEY_T,
	}
	for action in map:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		var ev := InputEventKey.new()
		ev.physical_keycode = map[action]
		InputMap.action_add_event(action, ev)


func _unhandled_input(event: InputEvent) -> void:
	# T: aborta a luta e volta pra tela de seleção de personagens.
	# O Roster é autoload, então a escolha atual segue válida ao voltar.
	if event.is_action_pressed("back_to_select"):
		get_viewport().set_input_as_handled()
		get_tree().change_scene_to_file(SELECT_SCENE)


func _build_world() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.06, 0.07, 0.11)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.6, 0.6, 0.7)
	e.ambient_light_energy = 0.7
	env.environment = e
	add_child(env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, -30.0, 0.0)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	add_child(sun)

	# luz de preenchimento vindo da direção da câmera (acende os rostos)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-25.0, 0.0, 0.0)
	fill.light_energy = 0.35
	add_child(fill)

	_build_arena()

	cam = Camera3D.new()
	cam.fov = 40.0
	add_child(cam)
	cam.current = true
	cam.global_position = Vector3(0.0, 2.2, 7.0)
	cam.look_at(Vector3(0.0, 1.1, 0.0))


func _build_arena() -> void:
	# chão: StaticBody3D (colisão) + malha (topo em y = -0.05)
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(22.0, 1.0, 7.0)
	shape.shape = box
	shape.position.y = -0.55
	floor_body.add_child(shape)
	floor_body.add_child(_make_box(Vector3(22.0, 1.0, 7.0), Vector3(0.0, -0.55, 0.0), Color(0.13, 0.14, 0.18)))
	add_child(floor_body)

	# faixa dourada em volta do tatame (borda)
	add_child(_make_box(Vector3(14.8, 0.04, 5.0), Vector3(0.0, -0.03, 0.0), Color(0.8, 0.66, 0.28)))
	# tatame vermelho (topo em y = 0, é onde os lutadores pisam)
	add_child(_make_box(Vector3(14.0, 0.05, 4.2), Vector3(0.0, -0.025, 0.0), Color(0.42, 0.17, 0.16)))

	# paredes ao redor (tijolo)
	add_child(_make_textured_box(Vector3(23.0, 4.5, 0.5), Vector3(0.0, 2.2, -3.9), WALL_TEX, 9.0))
	add_child(_make_textured_box(Vector3(0.5, 4.5, 8.5), Vector3(-11.25, 2.2, 0.0), WALL_TEX, 9.0))
	add_child(_make_textured_box(Vector3(0.5, 4.5, 8.5), Vector3(11.25, 2.2, 0.0), WALL_TEX, 9.0))
	# parapeito baixo na frente (1º plano)
	add_child(_make_textured_box(Vector3(23.0, 0.7, 0.5), Vector3(0.0, 0.3, 4.2), WALL_TEX, 9.0))

	# pilares nos cantos do tatame (metal enferrujado)
	for x in [-7.4, 7.4]:
		for z in [-2.9, 2.9]:
			add_child(_make_textured_box(Vector3(0.5, 3.4, 0.5), Vector3(x, 1.7, z), PILLAR_TEX, 1.6))

	# caixotes ao fundo (textura de madeira, uma cara por face)
	for x in [-5.6, -3.6, 3.6, 5.6]:
		add_child(_make_textured_box(Vector3(0.9, 0.9, 0.9), Vector3(x, 0.4, -3.2), CRATE_TEX, 0.0, false))


func _make_box(size: Vector3, pos: Vector3, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.9
	mi.mesh = bm
	mi.material_override = m
	mi.position = pos
	return mi


## Caixa com textura de cenário.
## tile_m > 0: triplanar no espaço do mundo, repetindo a cada tile_m
## metros (paredes/pilares — não distorce entre caixas de tamanhos
## diferentes nem entre faces de proporções diferentes).
## tile_m = 0: textura inteira em cada face (engradados — o UV natural
## do BoxMesh já mapeia 0..1 por face).
func _make_textured_box(size: Vector3, pos: Vector3, tex_path: String, tile_m := 0.0, use_triplanar: bool = true, tint := Color.WHITE) -> MeshInstance3D:
	var mi := _make_box(size, pos, tint)
	var tex := load(tex_path) as Texture2D
	if tex == null:
		push_warning("Textura do cenário não encontrada: %s" % tex_path)
		return mi
	var m := mi.material_override as StandardMaterial3D
	m.albedo_texture = tex
	if use_triplanar and tile_m > 0.0:
		m.uv1_triplanar = true
		m.uv1_world_triplanar = true
		m.uv1_scale = Vector3.ONE / tile_m
	return mi


func _build_audio() -> void:
	# trilha sonora (OGG/Vorbis) em looping eterno durante todo o jogo
	music = AudioStreamPlayer.new()
	var stream := load(MUSIC_STREAM) as AudioStreamOggVorbis
	if stream == null:
		push_warning("Trilha não encontrada: %s" % MUSIC_STREAM)
		return
	stream.loop = true
	music.stream = stream
	music.volume_db = -7.0
	add_child(music)
	music.play()


func _build_fighters() -> void:
	p1 = Fighter.new()
	p1.name = "Player1"
	p1.player_id = 1
	# personagem escolhido na tela de seleção (Roster.selected_slot)
	p1.character = Roster.get_selected()
	p2 = Fighter.new()
	p2.name = "Player2"
	p2.player_id = 2
	p2.is_ai = p2_is_ai
	# oponente padrão da CPU (enquanto P2 não tem tela de seleção)
	p2.character = Roster.opponent
	p1.opponent = p2
	p2.opponent = p1
	add_child(p1)
	add_child(p2)


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 20)
	root.add_child(top)
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = 24.0
	top.offset_right = -24.0
	top.offset_top = 16.0
	top.offset_bottom = 62.0

	bar1 = _make_bar(false, Color(0.2, 0.6, 1.0))
	bar2 = _make_bar(true, Color(1.0, 0.35, 0.3))
	timer_label = Label.new()
	timer_label.custom_minimum_size = Vector2(120.0, 0.0)
	timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	timer_label.add_theme_font_size_override("font_size", 26)
	top.add_child(bar1)
	top.add_child(timer_label)
	top.add_child(bar2)

	msg_label = Label.new()
	msg_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	msg_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	msg_label.add_theme_font_size_override("font_size", 64)
	msg_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(msg_label)

	var hint := Label.new()
	hint.text = "P1: A/D mover · J soco · K soco forte · L chute · ESPAÇO especial · S bloquear     P2: setas · , soco · . forte · / chute · ↓ bloquear     T: voltar pra seleção"
	hint.add_theme_font_size_override("font_size", 14)
	hint.modulate = Color(1.0, 1.0, 1.0, 0.65)
	hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	hint.offset_top = -36.0
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(hint)


func _make_bar(fill_end_to_begin: bool, color: Color) -> ProgressBar:
	var b := ProgressBar.new()
	b.max_value = 100
	b.value = 100
	b.show_percentage = false
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.custom_minimum_size = Vector2(0.0, 30.0)
	if fill_end_to_begin:
		b.fill_mode = ProgressBar.FILL_END_TO_BEGIN
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	b.add_theme_stylebox_override("fill", sb)
	return b


# ---------------------------------------------------------------- ROUNDS

func _start_round() -> void:
	p1.reset_for_round(Vector3(-START_X, 0.0, 0.0), 1)
	p2.reset_for_round(Vector3(START_X, 0.0, 0.0), -1)
	time_left = float(ROUND_TIME)
	phase = Phase.INTRO
	phase_frames = 0


func _physics_process(delta: float) -> void:
	phase_frames += 1
	match phase:
		Phase.INTRO:
			if phase_frames == 1:
				msg_label.text = "ROUND %d" % round_no
			elif phase_frames == 60:
				msg_label.text = "LUTAR!"
			elif phase_frames >= 100:
				msg_label.text = ""
				p1.combat_enabled = true
				p2.combat_enabled = true
				phase = Phase.FIGHT
				phase_frames = 0
		Phase.FIGHT:
			time_left = maxf(time_left - delta, 0.0)
			var ko1 := p1.state == Fighter.State.KO
			var ko2 := p2.state == Fighter.State.KO
			if ko1 or ko2 or time_left <= 0.0:
				var winner := 0
				if ko1 and ko2:
					winner = 0
				elif ko2:
					winner = 1
				elif ko1:
					winner = 2
				elif p1.hp > p2.hp:
					winner = 1
				elif p2.hp > p1.hp:
					winner = 2
				_end_round(winner, ko1 or ko2)
		Phase.ROUND_END:
			if phase_frames >= 150:
				if wins[0] >= ROUNDS_TO_WIN or wins[1] >= ROUNDS_TO_WIN:
					var champ := 1 if wins[0] > wins[1] else 2
					msg_label.text = "JOGADOR %d VENCEU!\nENTER para recomeçar" % champ
					phase = Phase.MATCH_END
				else:
					round_no += 1
					msg_label.text = ""
					_start_round()
		Phase.MATCH_END:
			if Input.is_action_just_pressed("ui_accept"):
				wins = [0, 0]
				round_no = 1
				msg_label.text = ""
				_start_round()


func _end_round(winner: int, by_ko: bool) -> void:
	phase = Phase.ROUND_END
	phase_frames = 0
	p1.combat_enabled = false
	p2.combat_enabled = false
	if winner == 0:
		msg_label.text = "EMPATE!"
	else:
		wins[winner - 1] += 1
		msg_label.text = "K.O.!" if by_ko else "TEMPO ESGOTADO!"
		if winner == 1:
			p1.play_taunt()
		else:
			p2.play_taunt()


# ---------------------------------------------------------------- FRAME

func _process(delta: float) -> void:
	bar1.max_value = p1.max_hp
	bar2.max_value = p2.max_hp
	bar1.value = p1.hp
	bar2.value = p2.hp
	timer_label.text = "%d\n%d - %d" % [ceili(time_left), wins[0], wins[1]]
	_update_camera(delta)


func _update_camera(delta: float) -> void:
	var a := p1.global_position
	var b := p2.global_position
	var mid := (a + b) * 0.5
	var dist := absf(a.x - b.x)
	var target := Vector3(mid.x, 2.0 + dist * 0.05, 6.5 + dist * 0.5)
	cam.global_position = cam.global_position.lerp(target, 1.0 - exp(-6.0 * delta))
	cam.look_at(Vector3(mid.x, 1.1, 0.0))
