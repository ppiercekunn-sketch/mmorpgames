extends SceneTree
## Minimal headless test runner (no addons needed).
## Run: godot --headless --path game --script res://tests/run_tests.gd
## Every file matching res://tests/test_*.gd is loaded; each method whose name
## starts with "test_" is called on a fresh instance. A test fails by calling
## fail("message") or assert_* helpers from TestCase. Exit code 1 on any failure.

const TEST_DIR := "res://tests"


func _initialize() -> void:
	var failures := 0
	var passed := 0
	var dir := DirAccess.open(TEST_DIR)
	for file_name in dir.get_files():
		if not file_name.begins_with("test_") or file_name.get_extension() != "gd":
			continue
		var script: GDScript = load(TEST_DIR.path_join(file_name))
		for method in script.get_script_method_list():
			var name: String = method["name"]
			if not name.begins_with("test_"):
				continue
			var test: TestCase = script.new()
			test.tree = self
			test.call(name)
			if test.failures.is_empty():
				passed += 1
			else:
				failures += 1
				for msg in test.failures:
					printerr("FAIL %s::%s - %s" % [file_name, name, msg])
	print("%d passed, %d failed" % [passed, failures])
	quit(1 if failures > 0 else 0)
