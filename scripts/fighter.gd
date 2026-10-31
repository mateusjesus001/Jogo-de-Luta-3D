extends Node3D
class_name Fighter
## Lutador genérico: recebe um CharacterData — a SKIN (modelo/textura) e
## os SEUS golpes (clips de animação) — monta as animações definidas no
## personagem e controla movimento, golpes e estados. O código não é
## preso a nenhum modelo específico.

enum State { IDLE, WALK, PUNCH, KICK, HIT, KO, TAUNT, SPECIAL }

const HIT_SFX := "res://soco carregado efeitos sonoros de dragon ball.wav"
const TARGET_HEIGHT := 1.8
const PUNCH_RANGE := 1.75
const PUNCH_HIT_TIME := 0.28
const PUNCH_SPEED := 1.3
const KICK_RANGE := 1.95
const KICK_SPEED := 1.1
## Combo de chutes no botão L: 1 aperto = chute 1 (Mma Kick); apertar de
## novo DURANTE o chute atual encadeia o próximo golpe do combo — no
## máximo 4 chutes, com o quarto sendo o finisher mais pesado.
const KICK_COMBO_MAX := 4
## Clips do combo, na ordem (chave no CharacterData.clips -> animação).
const KICK_CLIP_NAMES: Array[String] = ["kick", "kick2", "kick3", "kick4"]
## Fração do clip em que o chute conecta (~30% do Mma Kick, que batia
## com o hit fixo de 0.32s de antes — agora funciona pra qualquer clip).
const KICK_HIT_FRACTION := 0.3
## Passo do chute a partir do qual um "L" já pedido encadeia o próximo
## golpe na hora (em vez de esperar o fim do clip) — combo fluido.
const KICK_CHAIN_FRACTION := 0.7
## Validade do pedido de próximo golpe: apertar L durante o chute atual
## vale por COMBO_BUFFER_TIME segundos.
const COMBO_BUFFER_TIME := 0.45
## Dano do chute N = kick_damage * fator (o 4º é o finisher do combo).
const KICK_COMBO_DMG_FACTOR := [1.0, 1.15, 1.35, 1.8]
const WALK_ANIM_SPEED := 1.6
# especial à distância (Ednaldo/Nego Ney): energia que tira metade do HP
const SPECIAL_HIT_TIME := 5.5
## Seu Madruga: o impacto (dano + som) acontece 1s após o início da animação,
## sincronizado com o momento do soco na nuca — não espera o fim do clip.
const MADRUGA_SPECIAL_HIT_TIME := 1.0
## Nego Ney: a esfera sai 2s após o início da animação do feitiço —
## sincronizada com o momento em que ele estica o braço pra tacar a
## energia (o clip Magic Spell Casting dura ~4,27s; antes a esfera só
## saía no fim do clip porque SPECIAL_HIT_TIME passava do fim dele).
const NEGONEY_SPECIAL_HIT_TIME := 2.0
const SPECIAL_DURATION := 6.3
const SPECIAL_SPEED := 1.0
const BALL_SPEED := 14.0
const BALL_LIFE := 2.5
const BALL_RADIUS := 0.28
const KNOCKBACK := 0.35
const ARENA_LIMIT := 6.6
const SEPARATION := 0.9

static var _anim_cache: Dictionary = {}
static var _sfx_stream: AudioStream


@export var player_id := 1
@export var is_ai := false
## Personagem deste lutador: skin, golpes e stats (ver CharacterData).
@export var character: CharacterData

var opponent: Fighter
var max_hp := 100
var hp := 100
var state: State = State.IDLE
var combat_enabled := false
var facing := 1

var model: Node3D
var anim: AnimationPlayer
var _hit_audio: AudioStreamPlayer

var _act := "p1_"
var _base_y := 0.0
var _bob := 0.0
var _punch_t := 0.0
var _punch_hit_done := false
var _punch_heavy := false
var _kick_t := 0.0
var _kick_hit_done := false
## Passo atual do combo (1..4) e duração real do chute que está tocando.
var _kick_step := 1
var _kick_duration := 0.0
## Tempo restante do pedido bufferizado de próximo golpe do combo.
var _kick_buffer_t := 0.0
var _special_t := 0.0
var _special_hit_done := false
var _special_audio: AudioStreamPlayer
var _special_freeze_t := 0.0
var _balls: Array[Dictionary] = []
var _block_t := 0.0
var _ai_punch_cd := 1.0
## Fator aplicado nas tracks de POSIÇÃO das animações (1.0 = sem ajuste).
## O Model é escalado por s (pra ficar com ~1,8 m), mas as animações
## gravam posições ABSOLUTAS em unidades de mundo — sem dividir por s,
## a malha teleporta pra quilômetros de altura e "some" após 1 frame.
var _anim_pos_scale := 1.0


func _ready() -> void:
	_act = "p1_" if player_id == 1 else "p2_"
	if character == null:
		character = CharacterData.seu_madruga()
	max_hp = character.max_hp
	hp = max_hp
	_build_model()
	_setup_animations()
	_build_hit_audio()
	if character.special_sound != "":
		_build_special_audio()


func _build_hit_audio() -> void:
	_hit_audio = AudioStreamPlayer.new()
	_hit_audio.stream = _load_sfx()
	_hit_audio.volume_db = -10.0
	add_child(_hit_audio)


static func _load_sfx() -> AudioStream:
	if _sfx_stream == null:
		_sfx_stream = load(HIT_SFX) as AudioStream
	return _sfx_stream


func _build_special_audio() -> void:
	_special_audio = AudioStreamPlayer.new()
	_special_audio.stream = load(character.special_sound) as AudioStream
	_special_audio.volume_db = 3.0  # bem alto de propósito — é pra ser hilário 📢
	add_child(_special_audio)


## Instancia o modelo definido NO personagem (CharacterData.model_path)
## e aplica a skin dele — o código não conhece nenhum modelo específico.
func _build_model() -> void:
	var scene := load(character.model_path) as PackedScene
	if scene == null:
		push_error("Modelo do personagem não encontrado: %s" % character.model_path)
		model = Node3D.new()
	else:
		model = scene.instantiate()
	model.name = "Model"
	add_child(model)
	_setup_skin()


## Normaliza o modelo (1,8 m de altura, pés em y = 0) e aplica a skin:
## textura, se o personagem tiver; senão tinta plana (com escurecimento
## por parte, definido no próprio CharacterData).
func _setup_skin() -> void:
	var aabb := _model_aabb(model)
	var s := 1.0
	if aabb.size.y > 0.0001:
		s = TARGET_HEIGHT / aabb.size.y
	if not is_equal_approx(s, 1.0):
		model.scale = Vector3(s, s, s)
		# as tracks de posição vêm em unidades de mundo — anula o scale
		_anim_pos_scale = 1.0 / s
	# pés no chão: mede a AABB DEPOIS do scale aplicado (nas unidades do
	# modelo já escalado) e desloca o nó até o chão — era essa a conta do
	# setup antigo; multiplicar de novo pelo fator de escala jogava o
	# personagem pros ares.
	var box := _model_aabb(model)
	if box.size.y > 0.0001:
		model.position.y = -box.position.y
	_base_y = model.position.y
	if character.texture_path != "":
		_apply_texture()
	elif character.tint_color != Color.WHITE:
		_apply_tint()
	# garante que a malha nunca seja cortada pelo frustum culling
	for n in _all_meshes(model):
		(n as MeshInstance3D).custom_aabb = AABB(Vector3(-3, -0.5, -3), Vector3(6, 4, 6))


## Aplica a textura da skin (CharacterData.texture_path) com override,
## pra não mexer no material importado do modelo.
func _apply_texture() -> void:
	var tex := load(character.texture_path) as Texture2D
	if tex == null:
		push_warning("Textura não encontrada: %s" % character.texture_path)
		return
	for n in _all_meshes(model):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var src_mat := mi.get_active_material(i)
			var m := StandardMaterial3D.new()
			if src_mat is StandardMaterial3D:
				# herda a cor base caso o modelo venha com alguma tinta
				m.albedo_color = (src_mat as StandardMaterial3D).albedo_color
			m.albedo_texture = tex
			m.roughness = 0.8
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
			mi.set_surface_override_material(i, m)


## Tinta plana da skin (CharacterData.tint_color): pinta todas as malhas;
## partes citadas em tint_overrides recebem outra cor (ex.: juntas sombreadas).
func _apply_tint() -> void:
	var base := StandardMaterial3D.new()
	base.albedo_color = character.tint_color
	base.roughness = 0.65
	for n in _all_meshes(model):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		var mat := base
		var nname := String(mi.name).to_lower()
		for key in character.tint_overrides:
			if nname.contains(String(key)):
				mat = StandardMaterial3D.new()
				mat.albedo_color = character.tint_overrides[key]
				mat.roughness = 0.8
				break
		for i in mi.mesh.get_surface_count():
			mi.set_surface_override_material(i, mat)


## AABB combinada de todas as malhas (serve pra qualquer modelo).
static func _model_aabb(root: Node) -> AABB:
	var box := AABB()
	var first := true
	for n in _all_meshes(root):
		var mi := n as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		# AABB local da malha transformada até o root
		var t: Transform3D = root.get_global_transform().affine_inverse() * mi.get_global_transform()
		var b := t * mi.mesh.get_aabb()
		if first:
			box = b
			first = false
		else:
			box = box.merge(b)
	return box


static func _all_meshes(root: Node) -> Array:
	var out: Array = []
	_collect_meshes(root, out)
	return out


static func _collect_meshes(n: Node, out: Array) -> void:
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		_collect_meshes(c, out)


func _setup_animations() -> void:
	if model.has_node("AnimationPlayer"):
		anim = model.get_node("AnimationPlayer")
	else:
		anim = AnimationPlayer.new()
		anim.name = "AnimationPlayer"
		model.add_child(anim)
		anim.set_root_node(model.get_path())
	if not anim.has_animation_library(""):
		anim.add_animation_library("", AnimationLibrary.new())
	var lib := anim.get_animation_library("")
	var sk := _find_skeleton()
	# os golpes vêm do personagem: cada um tem o seu próprio moveset
	for key in character.clips:
		if not anim.has_animation(key):
			var clip: Animation = _load_clip(character.clips[key][0], character.clips[key][1], character.clips[key][2], sk, _anim_pos_scale)
			if clip != null:
				lib.add_animation(key, clip)
			else:
				push_warning("Clip '%s' não pôde ser carregado, ignorando." % key)
	if lib.has_animation(&"punch"):
		# os chutes do combo agacham o quadril de verdade: eleva ele pra
		# a altura do soco (que já fica na altura certa, em unidades de
		# modelo), de forma que vale pra qualquer modelo (Madruga 157x
		# ou Beta 1x). Vale pros 4 golpes do combo.
		for kick_name in KICK_CLIP_NAMES:
			if lib.has_animation(StringName(kick_name)):
				_clamp_hips_height(lib.get_animation(StringName(kick_name)), lib.get_animation(&"punch"), _anim_pos_scale)
		# a guarda (Center Block) afunda o quadril do mesmo jeito: aplica
		# a mesma correção usada nos chutes — sem ela, o lutador entra
		# no chão enquanto bloqueia.
		if lib.has_animation(&"block"):
			_clamp_hips_height(lib.get_animation(&"block"), lib.get_animation(&"punch"), _anim_pos_scale)
	# o especial (casting_spell) também desce o quadril: mesmo clamp do chute
	if lib.has_animation(&"casting_spell") and lib.has_animation(&"punch"):
		_clamp_hips_height(lib.get_animation(&"casting_spell"), lib.get_animation(&"punch"), _anim_pos_scale)
	anim.animation_finished.connect(_on_anim_finished)
	anim.play("idle")


static func _load_clip(fbx_path: String, clip_name: String, looped: bool, sk: Skeleton3D, pos_scale: float) -> Animation:
	var bone_sig := ""
	if sk != null:
		bone_sig = str(sk.get_bone_count()) + ":" + sk.get_bone_name(0)
	# v2: o chute passa por _clamp_hips_height DEPOIS do cache, então o
	# cache antigo (chute afundando) não pode ser reaproveitado.
	var cache_key := "v2|" + fbx_path + "|" + clip_name + "|" + bone_sig + "|" + str(pos_scale)
	if _anim_cache.has(cache_key):
		return _anim_cache[cache_key] as Animation
	# proteções: cada passo pode falhar (fbx ausente, sem AnimationPlayer,
	# clip interno com outro nome) — nunca crashar, sempre avisar.
	var packed := load(fbx_path) as PackedScene
	if packed == null:
		push_error("FBX não encontrado: %s" % fbx_path)
		return null
	var tmp := packed.instantiate()
	var src: AnimationPlayer = tmp.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if src == null:
		push_error("AnimationPlayer não encontrado em: %s" % fbx_path)
		tmp.free()
		return null
	# pega o clip pelo nome; se não existir, usa a primeira animação disponível
	var clip: Animation = null
	if src.has_animation(clip_name):
		clip = src.get_animation(clip_name)
	else:
		var names := src.get_animation_list()
		if names.size() > 0:
			clip = src.get_animation(names[0])
			push_warning("Clip '%s' não encontrado em %s — usando '%s'" % [clip_name, fbx_path, names[0]])
		else:
			push_error("Nenhuma animação em: %s" % fbx_path)
			tmp.free()
			return null
	var a: Animation = clip.duplicate() as Animation
	if sk != null:
		_retarget_to_skeleton(a, sk, pos_scale)
	if looped:
		a.loop_mode = Animation.LOOP_LINEAR
		_strip_root_motion(a)
	_anim_cache[cache_key] = a
	tmp.free()
	return a


## Acha o Skeleton3D do modelo (qualquer nome de nó).
func _find_skeleton() -> Skeleton3D:
	return _find_skeleton_in(model) as Skeleton3D


static func _find_skeleton_in(root: Node) -> Skeleton3D:
	if root is Skeleton3D:
		return root as Skeleton3D
	for n in _all_nodes(root):
		if n is Skeleton3D:
			return n as Skeleton3D
	return null


static func _all_nodes(root: Node) -> Array:
	var out: Array = []
	_collect_nodes(root, out)
	return out


static func _collect_nodes(n: Node, out: Array) -> void:
	out.append(n)
	for c in n.get_children():
		_collect_nodes(c, out)


## Remove tracks de ossos que não existem no esqueleto (ex: dedos no Madruga).
## Beta tem 65 ossos, Madruga tem 33 — os 33 principais têm o mesmo nome,
## então as 6 animações funcionam nos dois depois desse filtro.
## pos_scale divide as posições absolutas (Hips a ~1m) pelo fator de escala
## do Model, senão o Madruga teleporta pra 157m de altura e "some".
static func _retarget_to_skeleton(a: Animation, sk: Skeleton3D, pos_scale: float) -> void:
	var have := {}
	for b in sk.get_bone_count():
		have[sk.get_bone_name(b)] = true
	for t in range(a.get_track_count() - 1, -1, -1):
		var p := a.track_get_path(t)
		if str(p).begins_with("Skeleton3D:"):
			var bone := str(p).get_slice(":", 1)
			if not have.has(bone):
				a.remove_track(t)
				continue
			if pos_scale != 1.0 and a.track_get_type(t) == Animation.TYPE_POSITION_3D:
				var kc := a.track_get_key_count(t)
				for i in kc:
					var v: Vector3 = a.track_get_key_value(t, i)
					a.track_set_key_value(t, i, v * pos_scale)


## Remove o deslocamento linear do quadril (root motion) de clips em loop,
## pra o lutador não "descolar" do nó nem dar salto no fim do loop.
static func _strip_root_motion(a: Animation) -> void:
	for t in a.get_track_count():
		if a.track_get_type(t) != Animation.TYPE_POSITION_3D:
			continue
		var kc := a.track_get_key_count(t)
		if kc < 2:
			continue
		var dur: float = a.track_get_key_time(t, kc - 1)
		if dur <= 0.0:
			continue
		var drift: Vector3 = a.track_get_key_value(t, kc - 1) - a.track_get_key_value(t, 0)
		if drift.length() < 0.001:
			continue
		for i in kc:
			var kt: float = a.track_get_key_time(t, i)
			var v: Vector3 = a.track_get_key_value(t, i)
			a.track_set_key_value(t, i, v - drift * (kt / dur))


## Eleva as tracks de posição do quadril pra animação nunca afundar abaixo
## da altura de um golpe de referência (soco, que já fica na altura certa).
## O chute (Mma Kick) desce o quadril de verdade; o soco (Punch) fica
## na altura de descanso, então a diferença de altura entre os dois clipes
## é a "depth" do agachamento, medida nas unidades da escala do modelo.
## Método: recalculate lift da escala original, aplicar somente a diferença.
static func _clamp_hips_height(a: Animation, ref: Animation, _pos_scale: float) -> void:
	var base_y := _hips_height(ref, false)
	var min_y := _hips_height(a, false)
	if base_y == INF or min_y == INF:
		return
	var depth := base_y - min_y
	if depth <= 0.001:
		return
	# aplicar em escala de modelo: depth já está na escala da animação
	# (pois _retarget_to_skeleton multiplicou por pos_scale), então
	# adicionamos depth diretamente.
	for t in _hips_tracks(a):
		var kc := a.track_get_key_count(t)
		for i in kc:
			var v: Vector3 = a.track_get_key_value(t, i)
			a.track_set_key_value(t, i, v + Vector3(0.0, depth, 0.0))


## Tracks de posição do quadril (qualquer nome: Hips/mixamorig_Hips/...).
static func _hips_tracks(a: Animation) -> Array:
	var out: Array = []
	for t in a.get_track_count():
		if a.track_get_type(t) != Animation.TYPE_POSITION_3D:
			continue
		var bone := str(a.track_get_path(t)).get_slice(":", 1).to_lower()
		if bone.contains("hips"):
			out.append(t)
	return out


## Altura do quadril no clipe. first=true -> primeira chave (guarda);
## first=false -> Y minimo.
static func _hips_height(a: Animation, first: bool) -> float:
	if a == null:
		return INF
	var best := INF
	if first:
		for t in _hips_tracks(a):
			if a.track_get_key_count(t) > 0:
				var v: Vector3 = a.track_get_key_value(t, 0)
				best = minf(best, v.y)
	else:
		for t in _hips_tracks(a):
			var kc := a.track_get_key_count(t)
			for i in kc:
				var v: Vector3 = a.track_get_key_value(t, i)
				best = minf(best, v.y)
	return best


func _physics_process(delta: float) -> void:
	_bob += delta
	_block_t = maxf(_block_t - delta, 0.0)
	# congelado pelo especial do oponente: fica parado, sem input
	if _special_freeze_t > 0.0:
		_special_freeze_t -= delta
		if state == State.IDLE or state == State.WALK:
			state = State.IDLE
			if anim.current_animation != &"idle":
				anim.speed_scale = 1.0
				anim.play("idle")
		if _balls.size() > 0:
			_update_balls(delta)
		_separate()
		_animate_root()
		return
	if state == State.KO:
		return
	_face_opponent()
	match state:
		State.PUNCH:
			_punch_t += delta
			if not _punch_hit_done and _punch_t >= PUNCH_HIT_TIME:
				_punch_hit_done = true
				_resolve_hit()
		State.KICK:
			_kick_t += delta
			_kick_buffer_t = maxf(_kick_buffer_t - delta, 0.0)
			# apertar L DURANTE o chute pede o próximo golpe do combo
			# (o _human_control só roda em IDLE/WALK, então o input do
			# combo precisa ser lido aqui, enquanto o chute está ativo)
			if not is_ai and combat_enabled and Input.is_action_just_pressed(_act + "kick"):
				_kick_buffer_t = COMBO_BUFFER_TIME
			if not _kick_hit_done and _kick_t >= _kick_duration * KICK_HIT_FRACTION:
				_kick_hit_done = true
				_resolve_kick()
			# pediram o próximo golpe (L apertado de novo) e o chute atual
			# já passou da maior parte: encadeia na hora, sem esperar o fim.
			if _kick_buffer_t > 0.0 and _kick_step < KICK_COMBO_MAX and _kick_t >= _kick_duration * KICK_CHAIN_FRACTION:
				_advance_kick()
		State.SPECIAL:
			_special_t += delta
			var hit_time := SPECIAL_HIT_TIME
			if character.id == "seu_madruga":
				hit_time = MADRUGA_SPECIAL_HIT_TIME
			elif character.id == "negoney":
				hit_time = NEGONEY_SPECIAL_HIT_TIME
			if not _special_hit_done and _special_t >= hit_time:
				_special_hit_done = true
				if _is_ranged_special():
					_launch_energy_ball()
				elif character.id == "seu_madruga":
					_resolve_special_melee()
		State.HIT, State.TAUNT:
			pass
		_:
			if combat_enabled:
				if is_ai:
					_ai_control(delta)
				else:
					_human_control(delta)
			elif state != State.IDLE:
				state = State.IDLE
			# alterna entre a guarda (idle) e o passo agachado (walk) — só se o
			# estado continuou IDLE/WALK; um soco recém-iniciado vira PUNCH e
			# não pode ter a animação dele sobrescrita aqui.
			if state == State.IDLE or state == State.WALK:
				var want: StringName = &"walk" if state == State.WALK else &"idle"
				# parado E bloqueando (humano segurando S / guard da IA):
				# toca a animação de guarda (Center Block) no lugar do idle.
				# o _is_blocking cobre os dois casos, então humanos e CPU
				# usam a mesma animação — e se o personagem não tiver o
				# clip, cai no idle normal.
				if state == State.IDLE and _is_blocking() and anim.has_animation(&"block"):
					want = &"block"
				if anim.current_animation != want:
					anim.speed_scale = WALK_ANIM_SPEED if want == &"walk" else 1.0
					anim.play(want)
	if _balls.size() > 0:
		_update_balls(delta)
	_separate()
	_animate_root()


func _face_opponent() -> void:
	if opponent != null:
		facing = 1 if opponent.global_position.x >= global_position.x else -1
	rotation_degrees.y = facing * 90.0 + character.model_yaw


func _human_control(delta: float) -> void:
	var dir := 0
	if Input.is_action_pressed(_act + "left"):
		dir -= 1
	if Input.is_action_pressed(_act + "right"):
		dir += 1
	if dir != 0:
		global_position.x += dir * character.move_speed * delta
		state = State.WALK
	else:
		state = State.IDLE
	if Input.is_action_just_pressed(_act + "punch"):
		_start_punch(false)
	elif Input.is_action_just_pressed(_act + "heavy"):
		_start_punch(true)
	elif Input.is_action_just_pressed(_act + "kick"):
		_start_kick()
	elif Input.is_action_just_pressed(_act + "special"):
		_start_special()
	if Input.is_action_pressed(_act + "down"):
		_block_t = 0.1


func _ai_control(delta: float) -> void:
	_ai_punch_cd = maxf(_ai_punch_cd - delta, 0.0)
	if opponent == null:
		return
	var dx := opponent.global_position.x - global_position.x
	var dist := absf(dx)
	# às vezes defende o golpe
	if (opponent.state == State.PUNCH or opponent.state == State.KICK) and dist <= PUNCH_RANGE + 0.25 and _block_t <= 0.0:
		if randf() < 0.06:
			_block_t = 0.4
	if dist > 1.5:
		global_position.x += signf(dx) * character.move_speed * 0.85 * delta
		state = State.WALK
	elif _ai_punch_cd <= 0.0 and opponent.state != State.HIT:
		if randf() < 0.3:
			_start_kick()
		else:
			_start_punch(randf() < 0.3)
		_ai_punch_cd = randf_range(0.8, 1.7)
	else:
		state = State.IDLE


func _start_punch(heavy: bool) -> void:
	if state != State.IDLE and state != State.WALK:
		return
	state = State.PUNCH
	_punch_t = 0.0
	_punch_hit_done = false
	_punch_heavy = heavy
	anim.speed_scale = PUNCH_SPEED
	anim.play("punch")
	global_position.x += facing * 0.12


func _start_kick() -> void:
	if state != State.IDLE and state != State.WALK:
		return
	_start_kick_step(1)


## Toca o passo N do combo de chutes (1 = chute original). Usado pelo
## humano, pela IA e pelo encadeamento automático do combo.
func _start_kick_step(step: int) -> void:
	state = State.KICK
	_kick_step = step
	_kick_t = 0.0
	_kick_hit_done = false
	_kick_buffer_t = 0.0
	var clip_name := KICK_CLIP_NAMES[step - 1]
	if not anim.has_animation(clip_name):
		# personagem sem esse passo do combo: encerra o chute na hora
		push_warning("Animação '%s' não encontrada — combo de chute encerrado." % clip_name)
		_end_kick()
		return
	_kick_duration = anim.get_animation(clip_name).length / KICK_SPEED
	anim.speed_scale = KICK_SPEED
	anim.play(clip_name)
	global_position.x += facing * 0.15


## Próximo golpe do combo (chute 2, 3 ou 4 — o 4 é o finisher).
func _advance_kick() -> void:
	_start_kick_step(_kick_step + 1)


## Fim do combo de chutes: volta ao idle e zera a contagem.
func _end_kick() -> void:
	_kick_step = 1
	_kick_buffer_t = 0.0
	_to_idle()


## Especial à distância (esfera de energia): exclusivo de quem tem o clip
## do feitiço — hoje, Ednaldo Pereira e Nego Ney. O Seu Madruga é melee.
func _is_ranged_special() -> bool:
	return character.id == "ednaldo_pereira" or character.id == "negoney"


func _start_special() -> void:
	if state != State.IDLE and state != State.WALK:
		return
	if not _is_ranged_special() and character.id != "seu_madruga":
		return
	# À distância (Ednaldo/Nego Ney): som toca imediato (carregamento da energia).
	# Madruga: som só toca se o soco conectar (melee) — ver _resolve_special_melee.
	if _is_ranged_special() and _special_audio != null and _special_audio.stream != null:
		_special_audio.play()
	state = State.SPECIAL
	_special_t = 0.0
	_special_hit_done = false
	anim.speed_scale = SPECIAL_SPEED
	# congela o oponente durante o especial pra ele não cancelar a animação
	if opponent != null:
		opponent._special_freeze_t = SPECIAL_DURATION
	# só toca a animação se ela existir na biblioteca
	if anim.has_animation("casting_spell"):
		anim.play("casting_spell")
	else:
		push_warning("Animação 'casting_spell' não encontrada — usando 'idle'.")
		anim.play("idle")
	global_position.x += facing * 0.12


## Especial melee do Seu Madruga: só acerta se o oponente estiver no
## alcance do soco; o som só toca no acerto (não no início da animação).
func _resolve_special_melee() -> void:
	if opponent == null or opponent.state == State.KO:
		return
	var dist := absf(opponent.global_position.x - global_position.x)
	if dist > PUNCH_RANGE:
		return  # errou — sem som, sem dano (P2 já estava congelado)
	if _special_audio != null and _special_audio.stream != null:
		_special_audio.play()
	opponent.take_special_hit(character.special_damage)


func _resolve_kick() -> void:
	if opponent == null or opponent.state == State.KO:
		return
	var dist := absf(opponent.global_position.x - global_position.x)
	if dist > KICK_RANGE:
		return
	# dano escala com o passo do combo — o 4º golpe é o finisher
	var f: float = KICK_COMBO_DMG_FACTOR[mini(_kick_step - 1, KICK_COMBO_DMG_FACTOR.size() - 1)]
	var dmg := maxi(1, int(round(character.kick_damage * f)))
	var dir := signf(opponent.global_position.x - global_position.x)
	if dir == 0.0:
		dir = float(facing)
	opponent.take_hit(dmg, dir)
	if _hit_audio.stream != null:
		_hit_audio.play()


func _resolve_hit() -> void:
	if opponent == null or opponent.state == State.KO:
		return
	var dist := absf(opponent.global_position.x - global_position.x)
	if dist > PUNCH_RANGE:
		return
	var dmg := character.heavy_damage if _punch_heavy else character.punch_damage
	var dir := signf(opponent.global_position.x - global_position.x)
	if dir == 0.0:
		dir = float(facing)
	opponent.take_hit(dmg, dir)
	if _hit_audio.stream != null:
		_hit_audio.play()


func take_hit(damage: int, dir: float) -> void:
	if state == State.KO:
		return
	if dir == 0.0:
		dir = 1.0
	if _is_blocking():
		hp = maxi(hp - int(ceil(damage * 0.25)), 0)
		global_position.x += dir * 0.15
		if hp <= 0:
			_ko()
		return
	hp = maxi(hp - damage, 0)
	global_position.x += dir * KNOCKBACK
	if hp <= 0:
		_ko()
		return
	state = State.HIT
	anim.speed_scale = 1.0
	anim.play("hit")


func take_special_hit(factor: float) -> void:
	if state == State.KO:
		return
	var dmg := int(ceil(hp * factor))
	hp = maxi(hp - dmg, 0)
	global_position.x += facing * 0.2
	if hp <= 0:
		_ko()
		return
	state = State.HIT
	anim.speed_scale = 1.0
	anim.play("hit")


func _launch_energy_ball() -> void:
	if opponent == null:
		return
	var root := Node3D.new()
	root.name = "EnergyBall"
	var mesh := MeshInstance3D.new()
	mesh.mesh = SphereMesh.new()
	(mesh.mesh as SphereMesh).radius = BALL_RADIUS
	# cores vêm do personagem: Ednaldo = energia branco/azul (padrão),
	# Nego Ney = esfera preta (vilão) — ver CharacterData.ball_*.
	var c_ball: Color = character.ball_color
	var c_aura: Color = character.ball_aura_color
	var c_core: Color = character.ball_core_color
	var mat := StandardMaterial3D.new()
	mat.albedo_color = c_ball
	mat.emission = c_ball
	mat.emission_enabled = true
	mat.roughness = 0.1
	mat.metallic = 0.8
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.material_override = mat
	root.add_child(mesh)
	# aura externa azulada (energia grandiosa)
	var aura := MeshInstance3D.new()
	aura.mesh = SphereMesh.new()
	(aura.mesh as SphereMesh).radius = BALL_RADIUS * 2.0
	var mat2 := StandardMaterial3D.new()
	mat2.albedo_color = Color(c_aura.r, c_aura.g, c_aura.b, 0.35)
	mat2.emission = Color(c_aura.r, c_aura.g, c_aura.b, 0.6)
	mat2.emission_enabled = true
	mat2.roughness = 0.9
	mat2.metallic = 0.0
	mat2.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat2.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	aura.material_override = mat2
	root.add_child(aura)
	# core branco intenso no centro
	var core := MeshInstance3D.new()
	core.mesh = SphereMesh.new()
	(core.mesh as SphereMesh).radius = BALL_RADIUS * 0.45
	var mat3 := StandardMaterial3D.new()
	mat3.albedo_color = c_core
	mat3.emission = Color(c_core.r * 1.5, c_core.g * 1.5, c_core.b * 1.5)
	mat3.emission_enabled = true
	mat3.roughness = 0.05
	mat3.metallic = 0.9
	mat3.cull_mode = BaseMaterial3D.CULL_DISABLED
	core.material_override = mat3
	root.add_child(core)
	# sai da "mão" (na frente, altura do peito)
	var hand := global_position + Vector3(facing * 1.5, 1.5, 0.0)
	# entra na árvore ANTES de setar global_position: fora da árvore o
	# setter dá erro "!is_inside_tree()" e a bola spawnava fora de lugar.
	add_child(root)
	root.global_position = hand
	var dir := Vector3(facing, 0.0, 0.0).normalized()
	_balls.append({"node": root, "dir": dir, "life": 0.0})


func _update_balls(delta: float) -> void:
	var i := 0
	while i < _balls.size():
		var b := _balls[i]
		# guarda: dicionário mal formado ou nó da bola já destruído
		if b == null or not b.has("node") or not is_instance_valid(b.node):
			push_warning("Fighter._update_balls: bola sem nó válido, removendo.")
			_balls.remove_at(i)
			continue
		var ball: Node3D = b.node
		b.life += delta
		if not is_instance_valid(ball):
			push_warning("Fighter._update_balls: nó da bola se tornou inválido, removendo.")
			_balls.remove_at(i)
			continue
		ball.global_position += b.dir * BALL_SPEED * delta
		# pulso visual da energia
		var pulse := 1.0 + sin(b.life * 14.0) * 0.1
		ball.scale = Vector3(pulse, pulse, pulse)
		var hit := false
		# opponent pode ser um nó já destruído via queue_free(): != null não basta
		# compara só o eixo X: a esfera voa em y=1.5 e o oponente fica em y=0,
		# então distância 3D nunca ficaria abaixo do limiar
		if opponent != null and is_instance_valid(opponent) and opponent.state != State.KO:
			var dx := absf(ball.global_position.x - opponent.global_position.x)
			if dx < 1.2:
				hit = true
		if hit or b.life > BALL_LIFE or absf(ball.global_position.x) > ARENA_LIMIT * 1.5:
			if hit and opponent != null and is_instance_valid(opponent) and character != null:
				opponent.take_special_hit(character.special_damage)
				if _hit_audio != null and is_instance_valid(_hit_audio) and _hit_audio.stream != null:
					_hit_audio.play()
			if is_instance_valid(ball):
				ball.queue_free()
			_balls.remove_at(i)
		else:
			i += 1


func _is_blocking() -> bool:
	if _block_t > 0.0:
		return true
	if not is_ai and combat_enabled and (state == State.IDLE or state == State.WALK):
		return Input.is_action_pressed(_act + "down")
	return false


func _ko() -> void:
	hp = 0
	state = State.KO
	anim.speed_scale = 1.0
	anim.play("fall")
	model.position.y = _base_y
	model.rotation_degrees.x = 0.0


func reset_for_round(pos: Vector3, face_dir: int) -> void:
	global_position = pos
	hp = max_hp
	state = State.IDLE
	facing = face_dir
	rotation_degrees.y = facing * 90.0 + character.model_yaw
	_punch_t = 0.0
	_kick_t = 0.0
	_kick_step = 1
	_kick_buffer_t = 0.0
	_special_t = 0.0
	_special_hit_done = false
	_block_t = 0.0
	_ai_punch_cd = randf_range(0.6, 1.4)
	for b in _balls:
		b.node.queue_free()
	_balls.clear()
	combat_enabled = false
	if anim:
		anim.speed_scale = 1.0
		anim.play("idle")


func play_taunt() -> void:
	if anim == null or state == State.KO:
		return
	state = State.TAUNT
	anim.speed_scale = 1.0
	anim.play("taunt")


func _on_anim_finished(finished: StringName) -> void:
	# fim de um chute do combo (kick/kick2/kick3/kick4): se pediram o
	# próximo golpe (buffer válido), encadeia; senão termina o combo.
	if state == State.KICK and KICK_CLIP_NAMES.has(String(finished)):
		if _kick_buffer_t > 0.0 and _kick_step < KICK_COMBO_MAX:
			_advance_kick()
		else:
			_end_kick()
		return
	match finished:
		&"punch":
			if state == State.PUNCH:
				_to_idle()
		&"hit":
			if state == State.HIT:
				_to_idle()
		&"taunt":
			if state == State.TAUNT:
				_to_idle()
		&"casting_spell":
			if state == State.SPECIAL:
				# resolve o golpe na hora que a animação termina, antes de
				# voltar ao idle — assim funciona pra qualquer duração de clip
				if not _special_hit_done:
					_special_hit_done = true
					if _is_ranged_special():
						_launch_energy_ball()
					elif character.id == "seu_madruga":
						_resolve_special_melee()
				_to_idle()


func _to_idle() -> void:
	state = State.IDLE
	anim.speed_scale = 1.0
	anim.play("idle")


func _separate() -> void:
	if opponent != null:
		var dx := opponent.global_position.x - global_position.x
		var d := absf(dx)
		if d < SEPARATION and d > 0.0001:
			global_position.x -= signf(dx) * (SEPARATION - d) * 0.5
	global_position.x = clampf(global_position.x, -ARENA_LIMIT, ARENA_LIMIT)


func _animate_root() -> void:
	if state == State.IDLE:
		model.position.y = _base_y + sin(_bob * 3.0) * 0.012
		model.rotation_degrees.x = 0.0
	elif state == State.PUNCH or state == State.KICK or state == State.SPECIAL:
		# golpes que agacham o quadril (ex.: Mma Kick desce o Hips) não
		# podem afundar o modelo no tatame: trava a altura mínima.
		model.position.y = maxf(model.position.y, _base_y)
		model.rotation_degrees.x = 0.0
	else:
		model.position.y = _base_y
		model.rotation_degrees.x = 0.0
