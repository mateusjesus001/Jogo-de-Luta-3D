extends Resource
class_name CharacterData
## Definição de um personagem do roster (skin + golpes + stats).
## É o dado que o Roster guarda em cada slot da barra.
## Cada personagem tem a SUA skin (modelo + textura ou tinta) e os SEUS
## golpes (clips de animação), além dos stats de luta — assim o código do
## jogo não fica preso a um modelo específico.

## Clips genéricos do Mixamo usados como moveset padrão.
## nome da clip -> [arquivo .fbx, nome da animação dentro do fbx, em loop?]
const DEFAULT_CLIPS := {
	"idle": ["res://Action Idle To Fight Idle.fbx", "mixamo_com", true],
	"walk": ["res://Crouched Walking.fbx", "mixamo_com", true],
	"punch": ["res://Punch Combo.fbx", "mixamo_com", false],
	"kick": ["res://Mma Kick.fbx", "mixamo_com", false],
	"kick2": ["res://Second Kick.fbx", "mixamo_com", false],
	"kick3": ["res://Third.fbx", "mixamo_com", false],
	"kick4": ["res://Fourth.fbx", "mixamo_com", false],
	"block": ["res://Center Block.fbx", "mixamo_com", false],
	"hit": ["res://Stomach Hit.fbx", "mixamo_com", false],
	"fall": ["res://Falling Down.fbx", "mixamo_com", false],
	"taunt": ["res://Taunt.fbx", "mixamo_com", false],
}

## id estável do personagem.
@export var id := ""
## nome exibido (mesmo texto da placa da barra).
@export var display_name := ""
## false = slot bloqueado (cadeado) na tela de seleção.
@export var unlocked := false
## "" = slot vazio: espaço real guardado pra um futuro personagem.
@export var model_path := ""
## textura da skin ("" = não aplica textura).
@export var texture_path := ""
## arte da tela de seleção quando este personagem está escolhido
## (a imagem inteira da tela, com a barra e a plaquinha do nome).
@export var select_image := ""
## área da barra DENTRO da arte select_image (px): onde os 10 slots da
## barra estão desenhados. Medida na arte própria de cada personagem —
## se a arte for regenerada/alterada, refaça a medição dela.
@export var bar_rect := Rect2()
## tinta plana da skin quando não há textura própria.
@export var tint_color := Color.WHITE
## escurecimento por parte: {"trecho_do_nome_da_malha": cor}
@export var tint_overrides: Dictionary = {}
## offset de yaw do modelo (ajuste se ele ficar virado de costas).
@export var model_yaw := 0.0
## golpes do personagem: precisa das chaves idle/walk/punch/kick/hit/fall/taunt.
@export var clips: Dictionary = {}
## stats de luta.
@export var max_hp := 100
@export var move_speed := 3.2
@export var punch_damage := 8
@export var heavy_damage := 14
@export var kick_damage := 12
## Efeito especial do personagem (ex.: Casting Spell do Ednaldo): só
## o personagem dono da animação pode usá-lo. Vídeo: esfera de energia
## saindo da mão; som: arquivo .wav; dano: fração do HP do oponente.
@export var special_sound := ""
@export var special_damage := 0.0
## Cores da esfera de energia do especial à distância (Ednaldo/Nego Ney).
## Padrão: corpo branco + aura azul; Nego Ney usa preto (vilão).
@export var ball_color := Color(1.0, 1.0, 1.0)
@export var ball_aura_color := Color(0.4, 0.7, 1.0)
@export var ball_core_color := Color(1.0, 1.0, 1.0)


## Primeiro slot da barra — o Seu Madruga.
static func seu_madruga() -> CharacterData:
	var c := CharacterData.new()
	c.id = "seu_madruga"
	c.display_name = "SEU MADRUGA (ULTRA INSTINCT)"
	c.unlocked = true
	c.model_path = "res://seumadruga/seumadruga.fbx"
	c.texture_path = "res://seumadruga/texture_20250901.png"
	c.select_image = "res://characterselection/seumadrugaselecionado.png"
	c.bar_rect = Rect2(29.0, 17.0, 1084.0, 146.0)
	# todos os clips padrão + o especial exclusivo do personagem
	c.clips = DEFAULT_CLIPS.duplicate()
	# especial exclusivo do Seu Madruga — golpe corpo a corpo (melee)
	# Mixamo exporta a animação interna como "mixamo_com"
	c.clips["casting_spell"] = ["res://Zombie Punching.fbx", "mixamo_com", false]
	c.special_sound = "res://Zombie Punching.wav"
	c.special_damage = 0.5
	return c


## Segundo slot da barra — Nego Ney.
## model_path/texture_path já apontam pros arquivos da pasta negoney;
## o ajuste fino da importação entra no próximo passo.
static func negoney() -> CharacterData:
	var c := CharacterData.new()
	c.id = "negoney"
	c.display_name = "NEGO NEY (FULL POWER)"
	c.unlocked = true
	c.model_path = "res://negoney/8c6858b8f6bed8a7fffc60d6e79511a0.fbx"
	c.texture_path = "res://negoney/texture_20250901.png"
	c.select_image = "res://characterselection/negoneyselecionado.png"
	c.bar_rect = Rect2(30.0, 17.0, 1080.0, 156.0)
	# todos os clips padrão + o especial exclusivo do personagem
	# (duplicate(): sem isso, adicionar a chave aqui poluiria o
	# DEFAULT_CLIPS compartilhado pelo Akuma e pelo Beta)
	c.clips = DEFAULT_CLIPS.duplicate()
	# especial exclusivo do Nego Ney — esfera de energia à distância,
	# mesma lógica do Ednaldo (a esfera sai na hora do braço esticado;
	# a diferença é que a dele é PRETA, vilão)
	c.clips["casting_spell"] = ["res://Magic Spell Casting.fbx", "mixamo_com", false]
	# stats + efeito especial: som .ogg e dano em fração do HP (metade)
	c.special_sound = "res://Magic Spell Casting.ogg"
	c.special_damage = 0.5
	# esfera preta: corpo/albedo quase pretos e aura escura (visível
	# contra o cenário escuro) — ajuste as cores aqui se quiser
	c.ball_color = Color(0.03, 0.03, 0.04)
	c.ball_aura_color = Color(0.32, 0.32, 0.38)
	c.ball_core_color = Color(0.08, 0.08, 0.1)
	return c


## Terceiro slot da barra — Ednaldo Pereira.
## model_path/texture_path apontam pros arquivos da pasta ednaldopereira.
static func ednaldo_pereira() -> CharacterData:
	var c := CharacterData.new()
	c.id = "ednaldo_pereira"
	c.display_name = "EDNALDO PEREIRA"
	c.unlocked = true
	c.model_path = "res://ednaldopereira/1e07c5ecf5665824838eeb60f7514167.fbx"
	c.texture_path = "res://ednaldopereira/texture_20250901.png"
	c.select_image = "res://characterselection/ednaldopereiraselecionado.png"
	c.bar_rect = Rect2(31.0, 18.0, 1082.0, 143.0)
	# todos os clips padrão + o especial exclusivo do personagem
	c.clips = {
		"idle":   ["res://Action Idle To Fight Idle.fbx", "mixamo_com", true],
		"walk":   ["res://Crouched Walking.fbx", "mixamo_com", true],
		"punch":  ["res://Punch Combo.fbx", "mixamo_com", false],
		"kick":   ["res://Mma Kick.fbx", "mixamo_com", false],
		"kick2":  ["res://Second Kick.fbx", "mixamo_com", false],
		"kick3":  ["res://Third.fbx", "mixamo_com", false],
		"kick4":  ["res://Fourth.fbx", "mixamo_com", false],
		"hit":    ["res://Stomach Hit.fbx", "mixamo_com", false],
		"fall":   ["res://Falling Down.fbx", "mixamo_com", false],
		"taunt":  ["res://Taunt.fbx", "mixamo_com", false],
		# especial exclusivo do Ednaldo — só ele pode acionar
		# Mixamo exporta a animação interna como "mixamo_com", não o nome do fbx
		"casting_spell": ["res://Casting Spell.fbx", "mixamo_com", false],
	}
	# stats + efeito especial: dano em fração do HP do oponente + energia
	c.max_hp = 120
	c.move_speed = 3.4
	c.punch_damage = 9
	c.heavy_damage = 16
	c.kick_damage = 13
	# especial: armazena o som e o fator de dano (metade do HP)
	c.special_sound = "res://Casting Spell.wav"
	c.special_damage = 0.5
	return c


## Oponente da CPU — o Akuma (modelo riggado da pasta akuma/).
static func akuma() -> CharacterData:
	var c := CharacterData.new()
	c.id = "akuma"
	c.display_name = "AKUMA (BOSS)"
	c.unlocked = true
	c.model_path = "res://akuma/290b2f9a6896ea0b8457d605dfcffe7d.fbx"
	c.texture_path = "res://akuma/texture_20250901.png"
	# moveset padrão (soco, chute + combo de 4 chutes, hit, fall, taunt)
	c.clips = DEFAULT_CLIPS
	# stats de chefe: um pouco mais resistente e perigoso que o padrão
	c.max_hp = 115
	c.move_speed = 3.3
	c.punch_damage = 10
	c.heavy_damage = 16
	c.kick_damage = 14
	return c


## Oponente padrão da CPU — fica fora da barra enquanto P2 não tem
## tela de seleção.
static func beta() -> CharacterData:
	var c := CharacterData.new()
	c.id = "beta"
	c.display_name = "BETA"
	c.unlocked = true
	c.model_path = "res://Punch Combo.fbx"
	c.tint_color = Color(1.0, 0.3, 0.25)
	c.tint_overrides = {"joint": c.tint_color.darkened(0.5)}
	c.clips = DEFAULT_CLIPS
	return c


## Slot sem personagem: existe no jogo (espaço de verdade na barra),
## mas está bloqueado esperando alguém ocupá-lo.
static func slot_vazio(i: int) -> CharacterData:
	var c := CharacterData.new()
	c.id = "slot_%d" % i
	c.display_name = ""
	c.unlocked = false
	return c
