class_name ApiCodec
extends RefCounted
## Pure helpers for talking to the backend API (docs/api.md): URL building,
## headers, request bodies, response parsing and API URL overrides.
## Static functions only, no scene/autoload/network access, so tests and the
## M2 headless server can use them directly.

const MSG_NETWORK := "Can't reach the server. Check your connection and try again."
const MSG_TIMEOUT := "The server took too long to answer. Try again."
const MSG_BAD_RESPONSE := "Unexpected response from the server."
const MSG_UNAUTHORIZED := "Your session has expired. Please log in again."
const MSG_VALIDATION := "Please fix the highlighted fields."
const MSG_NOT_FOUND := "Not found."
const MSG_RATE_LIMITED := "Too many attempts. Wait a moment and try again."


## Trims whitespace and trailing slashes: " http://x/api/ " -> "http://x/api".
static func normalize_base_url(url: String) -> String:
	var clean := url.strip_edges()
	while clean.ends_with("/"):
		clean = clean.substr(0, clean.length() - 1)
	return clean


## True for absolute http(s) URLs with something after the scheme.
static func is_valid_base_url(url: String) -> bool:
	var clean := normalize_base_url(url)
	for scheme in ["http://", "https://"]:
		if clean.begins_with(scheme) and clean.length() > scheme.length():
			return true
	return false


## Turns an override into an absolute base URL. A path such as "/api" is
## resolved against `origin` (the page origin on web, e.g. "https://game.example").
## Returns "" when the value can't be used.
static func resolve_base_url(raw: String, origin: String = "") -> String:
	var clean := normalize_base_url(raw)
	if clean.begins_with("/") and origin != "":
		clean = normalize_base_url(origin) + clean
	return clean if is_valid_base_url(clean) else ""


## Joins base URL and endpoint path with exactly one slash between them.
static func build_url(base_url: String, path: String) -> String:
	var clean_path := path.strip_edges()
	while clean_path.begins_with("/"):
		clean_path = clean_path.substr(1)
	return normalize_base_url(base_url) + "/" + clean_path


static func character_path(character_id: int) -> String:
	return "characters/%d" % character_id


## Request headers. Content-Type is only sent with a body; the bearer token
## only when logged in.
static func build_headers(token: String, has_body: bool) -> PackedStringArray:
	var headers := PackedStringArray(["Accept: application/json"])
	if has_body:
		headers.append("Content-Type: application/json")
	if token != "":
		headers.append("Authorization: Bearer %s" % token)
	return headers


## JSON text for a request body; "" for no body.
static func encode_body(body: Dictionary) -> String:
	return "" if body.is_empty() else JSON.stringify(body)


## Converts an HTTPRequest completion into an ApiResult.
## `request_result` is the HTTPRequest.Result value, `body` the raw bytes.
static func parse_response(
	request_result: int, status_code: int, body: PackedByteArray
) -> ApiResult:
	return parse_response_text(request_result, status_code, body.get_string_from_utf8())


## Same as parse_response but takes the body as text (handy for tests).
static func parse_response_text(
	request_result: int, status_code: int, body_text: String
) -> ApiResult:
	if request_result != HTTPRequest.RESULT_SUCCESS or status_code == 0:
		return ApiResult.failure(0, network_error_message(request_result))

	var text := body_text.strip_edges()
	var data: Dictionary = {}
	var is_json := false
	if text != "":
		var json := JSON.new()
		if json.parse(text) == OK and typeof(json.data) == TYPE_DICTIONARY:
			data = json.data
			is_json = true

	if status_code >= 200 and status_code < 300:
		if text != "" and not is_json:
			return ApiResult.failure(status_code, MSG_BAD_RESPONSE)
		return ApiResult.success(status_code, data)

	var fields := extract_field_errors(data) if status_code == 422 else {}
	return ApiResult.failure(status_code, error_message_for(status_code, data), data, fields)


## Laravel 422 `errors` ({"field": ["msg", ...]}) -> {"field": "first msg"}.
static func extract_field_errors(data: Dictionary) -> Dictionary:
	var fields: Dictionary = {}
	var errors: Variant = data.get("errors", {})
	if typeof(errors) != TYPE_DICTIONARY:
		return fields
	for field in errors:
		var messages: Variant = errors[field]
		if typeof(messages) == TYPE_ARRAY and not messages.is_empty():
			fields[str(field)] = str(messages[0])
		elif typeof(messages) == TYPE_STRING:
			fields[str(field)] = messages
	return fields


## Message to show for a non-2xx response.
static func error_message_for(status_code: int, data: Dictionary) -> String:
	var server_message := str(data.get("message", "")).strip_edges()
	match status_code:
		401:
			return MSG_UNAUTHORIZED
		404:
			return server_message if server_message != "" else MSG_NOT_FOUND
		422:
			return server_message if server_message != "" else MSG_VALIDATION
		429:
			return MSG_RATE_LIMITED
	if status_code >= 500:
		return "The server had a problem (%d). Try again later." % status_code
	if server_message != "":
		return server_message
	return "Request failed (%d)." % status_code


## Message for an HTTPRequest.Result that is not RESULT_SUCCESS.
static func network_error_message(request_result: int) -> String:
	if request_result == HTTPRequest.RESULT_TIMEOUT:
		return MSG_TIMEOUT
	return MSG_NETWORK


## `data[key]` when it is an object, else {}.
static func extract_object(data: Dictionary, key: String) -> Dictionary:
	var value: Variant = data.get(key, {})
	return value if typeof(value) == TYPE_DICTIONARY else {}


## `data[key]` filtered to its object entries, else [].
static func extract_list(data: Dictionary, key: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var value: Variant = data.get(key, [])
	if typeof(value) != TYPE_ARRAY:
		return out
	for entry in value:
		if typeof(entry) == TYPE_DICTIONARY:
			out.append(entry)
	return out


## Character payload with JSON numbers (parsed as floats) turned into ints and
## missing fields defaulted, matching the shape of Session.start_offline().
static func normalize_character(raw: Dictionary) -> Dictionary:
	var character := raw.duplicate()
	for key in ["id", "level", "xp", "gold"]:
		character[key] = to_int(raw.get(key), 1 if key == "level" else 0)
	character["name"] = str(raw.get("name", ""))
	character["class"] = str(raw.get("class", ApiRules.CHARACTER_CLASS))
	character["birth_sign"] = str(raw.get("birth_sign", ""))
	return character


## Number-ish JSON value (int, float or numeric string) as int, else `fallback`.
static func to_int(value: Variant, fallback: int = 0) -> int:
	match typeof(value):
		TYPE_INT, TYPE_FLOAT:
			return int(value)
		TYPE_STRING:
			return value.to_int() if value.is_valid_int() else fallback
	return fallback


## Value of `key` in a URL query string ("?api=http%3A%2F%2Fx&y=1"), URL-decoded.
## Returns "" when absent.
static func query_param(query: String, key: String) -> String:
	var text := query.strip_edges()
	if text.begins_with("?"):
		text = text.substr(1)
	var hash_at := text.find("#")
	if hash_at >= 0:
		text = text.substr(0, hash_at)
	var pairs := text.split("&", false)
	for i in pairs.size():
		var pair: String = pairs[i]
		var eq: int = pair.find("=")
		var name: String = pair if eq < 0 else pair.substr(0, eq)
		if name.uri_decode() != key:
			continue
		var value: String = "" if eq < 0 else pair.substr(eq + 1)
		return value.replace("+", " ").uri_decode()
	return ""


## Value of a `--name=value` (or `--name value`) user argument; "" when absent.
static func arg_value(args: PackedStringArray, name: String) -> String:
	var flag := "--%s" % name
	for i in args.size():
		var arg := args[i]
		if arg.begins_with(flag + "="):
			return arg.substr(flag.length() + 1)
		if arg == flag and i + 1 < args.size() and not args[i + 1].begins_with("--"):
			return args[i + 1]
	return ""
