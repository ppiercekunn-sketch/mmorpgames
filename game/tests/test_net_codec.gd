extends TestCase
## ApiCodec: URL building, headers, bodies, overrides and response parsing.


func test_normalize_base_url_strips_space_and_slashes() -> void:
	assert_eq(ApiCodec.normalize_base_url("  http://x/api//  "), "http://x/api")


func test_build_url_joins_with_single_slash() -> void:
	assert_eq(ApiCodec.build_url("http://x/api", "auth/login"), "http://x/api/auth/login")
	assert_eq(ApiCodec.build_url("http://x/api/", "/me"), "http://x/api/me")
	assert_eq(ApiCodec.build_url("http://x/api", ApiCodec.character_path(7)),
		"http://x/api/characters/7")


func test_valid_base_urls() -> void:
	assert_true(ApiCodec.is_valid_base_url("http://localhost:8000/api"), "http")
	assert_true(ApiCodec.is_valid_base_url("https://game.example/api"), "https")
	assert_true(not ApiCodec.is_valid_base_url("ftp://x"), "ftp")
	assert_true(not ApiCodec.is_valid_base_url("https://"), "empty host")
	assert_true(not ApiCodec.is_valid_base_url(""), "empty")


func test_resolve_base_url_handles_relative_paths() -> void:
	assert_eq(ApiCodec.resolve_base_url("/api", "https://game.example"), "https://game.example/api")
	assert_eq(ApiCodec.resolve_base_url("https://other/api/"), "https://other/api")
	assert_eq(ApiCodec.resolve_base_url("/api"), "", "relative without origin")
	assert_eq(ApiCodec.resolve_base_url("javascript:alert(1)"), "", "bad scheme")


func test_headers_include_token_and_content_type_only_when_needed() -> void:
	var get_headers := ApiCodec.build_headers("", false)
	assert_eq(get_headers, PackedStringArray(["Accept: application/json"]))
	var post_headers := ApiCodec.build_headers("1|abc", true)
	assert_true("Content-Type: application/json" in post_headers, "content type")
	assert_true("Authorization: Bearer 1|abc" in post_headers, "bearer token")


func test_encode_body() -> void:
	assert_eq(ApiCodec.encode_body({}), "")
	var parsed: Variant = JSON.parse_string(ApiCodec.encode_body({"login": "alice"}))
	assert_eq(parsed, {"login": "alice"})


func test_query_param() -> void:
	var query := "?foo=1&api=http%3A%2F%2Flocalhost%3A8000%2Fapi&bar"
	assert_eq(ApiCodec.query_param(query, "api"), "http://localhost:8000/api")
	assert_eq(ApiCodec.query_param(query, "bar"), "")
	assert_eq(ApiCodec.query_param(query, "missing"), "")
	assert_eq(ApiCodec.query_param("api=https://x/api#top", "api"), "https://x/api")
	assert_eq(ApiCodec.query_param("", "api"), "")


func test_arg_value() -> void:
	var args := PackedStringArray(["--offline", "--api=http://h/api", "--x", "1"])
	assert_eq(ApiCodec.arg_value(args, "api"), "http://h/api")
	assert_eq(ApiCodec.arg_value(args, "x"), "1")
	assert_eq(ApiCodec.arg_value(args, "offline"), "")
	assert_eq(ApiCodec.arg_value(PackedStringArray(["--api", "http://h2/api"]), "api"),
		"http://h2/api")


func test_parse_success_json() -> void:
	var body := '{"token": "1|abc", "account": {"id": 1, "username": "alice"}}'
	var result := ApiCodec.parse_response_text(HTTPRequest.RESULT_SUCCESS, 201, body)
	assert_true(result.ok, "ok")
	assert_eq(result.status, 201)
	assert_eq(result.data["token"], "1|abc")
	assert_eq(result.error_message, "")


func test_parse_bytes_matches_text() -> void:
	var body := '{"characters": []}'
	var result := ApiCodec.parse_response(HTTPRequest.RESULT_SUCCESS, 200, body.to_utf8_buffer())
	assert_true(result.ok, "ok")
	assert_eq(result.data, {"characters": []})


func test_parse_no_content() -> void:
	var result := ApiCodec.parse_response_text(HTTPRequest.RESULT_SUCCESS, 204, "")
	assert_true(result.ok, "204 ok")
	assert_eq(result.data, {})


func test_parse_non_json_success_is_error() -> void:
	var result := ApiCodec.parse_response_text(HTTPRequest.RESULT_SUCCESS, 200, "<html>hi</html>")
	assert_true(not result.ok, "not ok")
	assert_eq(result.error_message, ApiCodec.MSG_BAD_RESPONSE)


func test_parse_validation_errors() -> void:
	var body := (
		'{"message": "The username has already been taken. (and 1 more error)",'
		+ ' "errors": {"username": ["The username has already been taken."],'
		+ ' "email": ["The email field must be a valid email address.", "Second"]}}'
	)
	var result := ApiCodec.parse_response_text(HTTPRequest.RESULT_SUCCESS, 422, body)
	assert_true(not result.ok, "not ok")
	assert_eq(result.status, 422)
	assert_true(result.has_field_errors(), "has field errors")
	assert_eq(result.field_error("username"), "The username has already been taken.")
	assert_eq(result.field_error("email"), "The email field must be a valid email address.")
	assert_eq(result.field_error("password"), "")
	assert_true(result.error_message.begins_with("The username"), "server message kept")


func test_parse_unauthorized() -> void:
	var body := '{"message": "Unauthenticated."}'
	var result := ApiCodec.parse_response_text(HTTPRequest.RESULT_SUCCESS, 401, body)
	assert_true(result.is_unauthorized(), "401")
	assert_eq(result.error_message, ApiCodec.MSG_UNAUTHORIZED)


func test_parse_server_error_with_html_body() -> void:
	var result := ApiCodec.parse_response_text(HTTPRequest.RESULT_SUCCESS, 500, "<h1>Oops</h1>")
	assert_true(not result.ok, "not ok")
	assert_eq(result.error_message, "The server had a problem (500). Try again later.")


func test_parse_network_failures() -> void:
	var refused := ApiCodec.parse_response_text(HTTPRequest.RESULT_CANT_CONNECT, 0, "")
	assert_true(refused.is_network_error(), "network error")
	assert_eq(refused.error_message, ApiCodec.MSG_NETWORK)
	var timeout := ApiCodec.parse_response_text(HTTPRequest.RESULT_TIMEOUT, 0, "")
	assert_eq(timeout.error_message, ApiCodec.MSG_TIMEOUT)


func test_extract_helpers() -> void:
	var data := {"characters": [{"id": 1}, "junk", {"id": 2}], "character": {"id": 3}}
	assert_eq(ApiCodec.extract_list(data, "characters").size(), 2)
	assert_eq(ApiCodec.extract_list(data, "missing").size(), 0)
	assert_eq(ApiCodec.extract_object(data, "character"), {"id": 3})
	assert_eq(ApiCodec.extract_object(data, "characters"), {})


func test_normalize_character_converts_json_numbers() -> void:
	var raw: Dictionary = JSON.parse_string(
		'{"id": 7, "name": "Aldric", "class": "warrior", "birth_sign": "aries",'
		+ ' "level": 3, "xp": 120, "gold": 15, "created_at": "2026-10-27T12:00:00Z"}'
	)
	var character := ApiCodec.normalize_character(raw)
	assert_eq(typeof(character["id"]), TYPE_INT, "id is int")
	assert_eq(character["id"], 7)
	assert_eq(character["level"], 3)
	assert_eq(character["name"], "Aldric")
	assert_eq(character["created_at"], "2026-10-27T12:00:00Z", "extra fields kept")
	var sparse := ApiCodec.normalize_character({"id": null, "name": "X"})
	assert_eq(sparse["id"], 0)
	assert_eq(sparse["level"], 1)
	assert_eq(sparse["class"], "warrior")
