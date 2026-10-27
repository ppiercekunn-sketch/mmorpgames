extends TestCase


func test_level_one_defaults() -> void:
	var s := Stats.new()
	assert_eq(s.max_hp(), 220, "max_hp")
	assert_eq(s.max_mp(), 110, "max_mp")
	assert_eq(s.attack(), 23, "attack")


func test_bonuses_apply() -> void:
	var s := Stats.new()
	s.bonuses = {"attack": 5, "max_hp": 40}
	assert_eq(s.attack(), 28, "attack")
	assert_eq(s.max_hp(), 260, "max_hp")


func test_crit_is_capped() -> void:
	var s := Stats.new()
	s.bonuses = {"crit_chance": 5.0}
	assert_near(s.crit_chance(), 0.75)
