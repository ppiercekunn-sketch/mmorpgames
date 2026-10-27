class_name TestCase
extends RefCounted
## Base class for tests run by run_tests.gd. Extend it in res://tests/test_*.gd.
## Tests run outside the main scene tree, so autoloads (Events, GameData) are
## NOT available; keep tested logic in plain scripts/Resources.

var tree: SceneTree
var failures: Array[String] = []


func fail(msg: String) -> void:
	failures.append(msg)


func assert_true(cond: bool, msg: String = "expected true") -> void:
	if not cond:
		fail(msg)


func assert_eq(actual: Variant, expected: Variant, msg: String = "") -> void:
	if actual != expected:
		fail("%s expected %s, got %s" % [msg, str(expected), str(actual)])


func assert_near(actual: float, expected: float, eps: float = 0.0001, msg: String = "") -> void:
	if absf(actual - expected) > eps:
		fail("%s expected ~%s, got %s" % [msg, str(expected), str(actual)])
