class_name SkillCooldowns
extends RefCounted
## Tracks per-skill cooldowns from elapsed time. Pure logic: call tick(delta)
## once per frame (or with any elapsed time on the server).

## skill_id -> seconds left
var _remaining: Dictionary = {}
## skill_id -> full duration of the cooldown currently running
var _durations: Dictionary = {}


## Starts (or restarts) the cooldown of `skill_id`.
func start(skill_id: String, duration: float) -> void:
	if duration <= 0.0:
		_remaining.erase(skill_id)
		_durations.erase(skill_id)
		return
	_remaining[skill_id] = duration
	_durations[skill_id] = duration


## Advances every running cooldown by `elapsed` seconds.
func tick(elapsed: float) -> void:
	for skill_id: Variant in _remaining.keys():
		var left: float = float(_remaining[skill_id]) - elapsed
		if left <= 0.0:
			_remaining.erase(skill_id)
			_durations.erase(skill_id)
		else:
			_remaining[skill_id] = left


## Seconds until `skill_id` can be used again (0 when ready).
func remaining(skill_id: String) -> float:
	return float(_remaining.get(skill_id, 0.0))


func is_ready(skill_id: String) -> bool:
	return remaining(skill_id) <= 0.0


## Remaining fraction of the running cooldown: 1.0 just after use, 0.0 when ready.
func fraction(skill_id: String) -> float:
	var duration: float = float(_durations.get(skill_id, 0.0))
	if duration <= 0.0:
		return 0.0
	return clampf(remaining(skill_id) / duration, 0.0, 1.0)


func reset_all() -> void:
	_remaining.clear()
	_durations.clear()
