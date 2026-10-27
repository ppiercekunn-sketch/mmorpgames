extends TestCase
## ApiRules (client-side copies of the backend validation rules) and ApiResult.


func test_username_rules() -> void:
	assert_eq(ApiRules.validate_username("alice_01"), "")
	assert_true(ApiRules.validate_username("al") != "", "too short")
	assert_true(ApiRules.validate_username("a".repeat(21)) != "", "too long")
	assert_true(ApiRules.validate_username("bad name") != "", "space")
	assert_true(ApiRules.validate_username("ali-ce") != "", "dash")


func test_email_rules() -> void:
	assert_eq(ApiRules.validate_email("alice@example.com"), "")
	assert_true(ApiRules.validate_email("") != "", "empty")
	assert_true(ApiRules.validate_email("alice@") != "", "no domain")
	assert_true(ApiRules.validate_email("alice example.com") != "", "no at")


func test_password_rules() -> void:
	assert_eq(ApiRules.validate_password("secret123"), "")
	assert_true(ApiRules.validate_password("short") != "", "too short")
	assert_eq(ApiRules.validate_password_confirmation("secret123", "secret123"), "")
	assert_true(ApiRules.validate_password_confirmation("secret123", "secret124") != "")


func test_character_name_rules() -> void:
	assert_eq(ApiRules.validate_character_name("Aldric"), "")
	assert_eq(ApiRules.validate_character_name("Al2"), "")
	assert_true(ApiRules.validate_character_name("Al") != "", "too short")
	assert_true(ApiRules.validate_character_name("A".repeat(17)) != "", "too long")
	assert_true(ApiRules.validate_character_name("Al_dric") != "", "underscore")


func test_login_form() -> void:
	assert_eq(ApiRules.validate_login_form("alice", "x"), {})
	var errors := ApiRules.validate_login_form("  ", "")
	assert_true(errors.has("login"), "login")
	assert_true(errors.has("password"), "password")


func test_register_form_uses_api_field_names() -> void:
	assert_eq(ApiRules.validate_register_form("alice", "a@b.co", "secret123", "secret123"), {})
	var errors := ApiRules.validate_register_form("a", "nope", "short", "other")
	assert_eq(errors.keys().size(), 4)
	for field in ["username", "email", "password", "password_confirmation"]:
		assert_true(errors.has(field), field)


func test_character_form() -> void:
	var signs := ["aries", "taurus"]
	assert_eq(ApiRules.validate_character_form("Aldric", "aries", signs), {})
	assert_true(ApiRules.validate_character_form("Aldric", "", signs).has("birth_sign"), "none")
	assert_true(ApiRules.validate_character_form("Aldric", "ophiuchus", signs).has("birth_sign"))
	assert_eq(ApiRules.validate_character_form("Aldric", "ophiuchus"), {}, "no sign list")
	assert_true(ApiRules.validate_character_form("x", "aries", signs).has("name"), "name")


func test_result_helpers() -> void:
	var ok := ApiResult.success(200, {"a": 1})
	assert_true(ok.ok and not ok.is_network_error() and not ok.has_field_errors(), "success")
	var bad := ApiResult.failure(422, "Fix it", {}, {"name": "Taken"})
	assert_eq(bad.field_error("name"), "Taken")
	assert_eq(bad.to_dict()["status"], 422)
	assert_eq(bad.to_dict()["field_errors"], {"name": "Taken"})
	assert_true(ApiResult.failure(0, "down").is_network_error(), "network")
