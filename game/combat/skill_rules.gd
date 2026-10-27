class_name SkillRules
extends RefCounted
## Pure rules for skills defined in data/skills.json: whether a cast is
## allowed, range checks and hotbar ordering. No scene or autoload deps.
##
## Skill entry fields: name, slot (1-6), mp_cost, cooldown, range, power,
## aoe_radius, effect, duration, buff_amount, description, unlock_level.
## Effects:
##   "damage"       single-target hit for power x attack
##   "charge"       dash to the target, then hit it
##   "aoe_damage"   hit every hostile within aoe_radius around the caster
##   "buff_attack"  attack x (1 + buff_amount) for `duration` seconds
##   "buff_defense" damage taken x (1 - buff_amount) for `duration` seconds

const CAN_CAST := ""
const LOCKED := "locked"
const NOT_ENOUGH_MP := "not_enough_mp"
const ON_COOLDOWN := "on_cooldown"
const NO_TARGET := "no_target"
const UNKNOWN := "unknown_skill"

const TARGETED_EFFECTS: Array[String] = ["damage", "charge"]


## True when the skill must be aimed at the current target.
static func needs_target(skill: Dictionary) -> bool:
	return str(skill.get("effect", "")) in TARGETED_EFFECTS


static func is_unlocked(skill: Dictionary, caster_level: int) -> bool:
	return caster_level >= int(skill.get("unlock_level", 1))


## Returns CAN_CAST ("") when the skill can be cast now, otherwise a reason
## constant. Range is checked separately: an out-of-range cast walks into
## range first.
static func check_cast(
	skill: Dictionary, caster_level: int, caster_mp: int, cooldown_left: float, has_target: bool
) -> String:
	var reason := CAN_CAST
	if skill.is_empty():
		reason = UNKNOWN
	elif not is_unlocked(skill, caster_level):
		reason = LOCKED
	elif cooldown_left > 0.0:
		reason = ON_COOLDOWN
	elif caster_mp < int(skill.get("mp_cost", 0)):
		reason = NOT_ENOUGH_MP
	elif needs_target(skill) and not has_target:
		reason = NO_TARGET
	return reason


## A skill with range <= 0 (self-centred) is always in range.
static func in_range(skill: Dictionary, distance: float) -> bool:
	var skill_range: float = float(skill.get("range", 0.0))
	return skill_range <= 0.0 or distance <= skill_range


## Skill ids ordered by their "slot" field, i.e. hotbar order.
static func ordered_slots(table: Dictionary) -> Array[String]:
	var ids: Array[String] = []
	for key: Variant in table:
		ids.append(str(key))
	ids.sort_custom(
		func(a: String, b: String) -> bool: return _slot_of(table, a) < _slot_of(table, b)
	)
	return ids


## Player-facing message for a failed cast.
static func reason_text(reason: String) -> String:
	var text := ""
	match reason:
		LOCKED:
			text = "Skill not learned yet"
		NOT_ENOUGH_MP:
			text = "Not enough MP"
		ON_COOLDOWN:
			text = "Skill is not ready"
		NO_TARGET:
			text = "No target"
		UNKNOWN:
			text = "Unknown skill"
	return text


static func _slot_of(table: Dictionary, skill_id: String) -> int:
	var entry: Variant = table.get(skill_id, {})
	if entry is Dictionary:
		return int((entry as Dictionary).get("slot", 99))
	return 99
