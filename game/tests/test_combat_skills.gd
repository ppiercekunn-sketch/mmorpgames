extends TestCase

const Cooldowns := preload("res://combat/skill_cooldowns.gd")
const Rules := preload("res://combat/skill_rules.gd")

const STRIKE := {
	"name": "Heavy Strike",
	"slot": 1,
	"mp_cost": 8,
	"cooldown": 4.0,
	"range": 60.0,
	"effect": "damage",
	"unlock_level": 1
}
const WAR_CRY := {
	"name": "War Cry",
	"slot": 4,
	"mp_cost": 15,
	"cooldown": 20.0,
	"range": 0.0,
	"effect": "buff_attack",
	"unlock_level": 6
}


func test_cooldown_counts_down() -> void:
	var cd := Cooldowns.new()
	assert_true(cd.is_ready("a"), "ready before use")
	cd.start("a", 4.0)
	assert_true(not cd.is_ready("a"), "not ready after start")
	assert_near(cd.fraction("a"), 1.0)
	cd.tick(1.0)
	assert_near(cd.remaining("a"), 3.0)
	assert_near(cd.fraction("a"), 0.75)
	cd.tick(2.5)
	assert_near(cd.remaining("a"), 0.5)
	cd.tick(0.6)
	assert_true(cd.is_ready("a"), "ready after full duration")
	assert_near(cd.fraction("a"), 0.0)


func test_cooldowns_are_independent() -> void:
	var cd := Cooldowns.new()
	cd.start("a", 1.0)
	cd.start("b", 5.0)
	cd.tick(2.0)
	assert_true(cd.is_ready("a"), "a ready")
	assert_true(not cd.is_ready("b"), "b still cooling")
	cd.reset_all()
	assert_true(cd.is_ready("b"), "reset clears")


func test_zero_cooldown_is_always_ready() -> void:
	var cd := Cooldowns.new()
	cd.start("a", 0.0)
	assert_true(cd.is_ready("a"), "zero cooldown")


func test_check_cast_reasons() -> void:
	assert_eq(Rules.check_cast(STRIKE, 1, 50, 0.0, true), Rules.CAN_CAST, "ok")
	assert_eq(Rules.check_cast(STRIKE, 1, 5, 0.0, true), Rules.NOT_ENOUGH_MP, "mp")
	assert_eq(Rules.check_cast(STRIKE, 1, 50, 1.0, true), Rules.ON_COOLDOWN, "cooldown")
	assert_eq(Rules.check_cast(STRIKE, 1, 50, 0.0, false), Rules.NO_TARGET, "target")
	assert_eq(Rules.check_cast(WAR_CRY, 5, 50, 0.0, false), Rules.LOCKED, "locked")
	assert_eq(Rules.check_cast(WAR_CRY, 6, 50, 0.0, false), Rules.CAN_CAST, "self buff")
	assert_eq(Rules.check_cast({}, 10, 999, 0.0, true), Rules.UNKNOWN, "unknown")


func test_range_check() -> void:
	assert_true(Rules.in_range(STRIKE, 59.0), "inside")
	assert_true(not Rules.in_range(STRIKE, 61.0), "outside")
	assert_true(Rules.in_range(WAR_CRY, 9999.0), "self-centred")


func test_ordered_slots() -> void:
	var table := {"war_cry": WAR_CRY, "heavy_strike": STRIKE}
	var ids := Rules.ordered_slots(table)
	assert_eq(ids.size(), 2, "count")
	assert_eq(ids[0], "heavy_strike", "slot 1 first")
	assert_eq(ids[1], "war_cry", "slot 4 second")
