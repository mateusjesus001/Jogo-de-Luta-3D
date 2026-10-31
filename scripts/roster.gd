extends Node
## Roster de personagens: os slots REAIS da barra da tela de seleção.
##
## A barra tem SLOT_COUNT espaços. O slot 0 está com o Seu Madruga; os
## demais são cadeados, mas cada um já guarda um espaço de verdade no
## jogo pra um futuro personagem (CharacterData sem modelo = slot vazio).
## Pra liberar alguém: troque CharacterData.slot_vazio(i) pelo personagem
## em _montar_slots() — a área de clique da tela de seleção já existe.

const SLOT_COUNT := 10

## Personagem de cada espaço da barra (vazio = cadeado).
var slots: Array[CharacterData] = []
## Índice do slot escolhido na tela de seleção.
var selected_slot := 0
## Oponente padrão da luta (CPU) — P2 ainda não tem tela de escolha.
var opponent: CharacterData


func _ready() -> void:
	_montar_slots()
	opponent = CharacterData.akuma()
	select_slot(0)


func _montar_slots() -> void:
	slots.clear()
	for i in SLOT_COUNT:
		if i == 0:
			# primeiro slot da barra: o Seu Madruga
			slots.append(CharacterData.seu_madruga())
		elif i == 1:
			# segundo slot da barra: o Nego Ney
			slots.append(CharacterData.negoney())
		elif i == 2:
			# terceiro slot da barra: o Ednaldo Pereira
			slots.append(CharacterData.ednaldo_pereira())
		else:
			# cadeado: slot real, reservado pra um personagem futuro
			slots.append(CharacterData.slot_vazio(i))


func get_slot(i: int) -> CharacterData:
	if i < 0 or i >= slots.size():
		return null
	return slots[i]


## O slot tem personagem e está liberado?
func is_selectable(i: int) -> bool:
	var c := get_slot(i)
	return c != null and c.unlocked and c.model_path != ""


## Clica num slot da barra. false = slot bloqueado (cadeado).
func select_slot(i: int) -> bool:
	if not is_selectable(i):
		return false
	selected_slot = i
	return true


## O que a luta vai importar: personagem escolhido na tela de seleção.
func get_selected() -> CharacterData:
	if is_selectable(selected_slot):
		return get_slot(selected_slot)
	for i in slots.size():
		if is_selectable(i):
			selected_slot = i
			return get_slot(i)
	return CharacterData.seu_madruga()
