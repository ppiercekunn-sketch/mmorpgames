class_name ApiClient
extends Node
## Async client for the backend API (docs/api.md). Add it to the tree, then:
##     var result := await api.login("alice", "secret123")
##     if result.ok: ...
## Every call returns an ApiResult. Uses Session.api_base_url and
## Session.token; login/register store the token in Session, logout and any
## 401 clear it. Parsing and URL building live in ApiCodec (pure, tested).

## Emitted after a request with a token got 401. Session is already cleared.
signal unauthorized

const DEFAULT_TIMEOUT_SEC := 15.0
## Web: `index.html?api=https://host/api` overrides the API base URL.
const QUERY_PARAM := "api"
## Web: `window.POCKIE_API_URL` (e.g. set in the HTML shell) overrides it too.
const JS_GLOBAL := "POCKIE_API_URL"
## Desktop: `godot --path game -- --api=http://host/api`.
const CMDLINE_ARG := "api"

## Seconds before a request is abandoned (HTTPRequest.timeout).
var timeout_sec: float = DEFAULT_TIMEOUT_SEC

var _in_flight: int = 0


func _ready() -> void:
	apply_api_override()


## True while at least one request is waiting for an answer.
func is_busy() -> bool:
	return _in_flight > 0


## Applies a base URL override from the page URL / JS global (web) or the
## command line (desktop) to Session.api_base_url. Returns the URL in use.
func apply_api_override() -> String:
	var override := detect_api_override()
	if override != "":
		Session.api_base_url = override
	return Session.api_base_url


## The override URL, or "" when none is given (or it is invalid).
static func detect_api_override() -> String:
	if OS.has_feature("web"):
		var origin := _js_string("window.location.origin")
		var from_query := ApiCodec.query_param(_js_string("window.location.search"), QUERY_PARAM)
		if from_query != "":
			return ApiCodec.resolve_base_url(from_query, origin)
		var from_global := _js_string("window.%s || ''" % JS_GLOBAL)
		if from_global != "":
			return ApiCodec.resolve_base_url(from_global, origin)
		return ""
	var from_args := ApiCodec.arg_value(OS.get_cmdline_user_args(), CMDLINE_ARG)
	return ApiCodec.resolve_base_url(from_args) if from_args != "" else ""


# --- Auth -------------------------------------------------------------------


## POST /auth/register. On success Session.token and Session.account are set.
func register(
	username: String, email: String, password: String, password_confirmation: String
) -> ApiResult:
	var body := {
		"username": username.strip_edges(),
		"email": email.strip_edges(),
		"password": password,
		"password_confirmation": password_confirmation,
	}
	var result := await _send(HTTPClient.METHOD_POST, "auth/register", body, false)
	return _store_auth(result)


## POST /auth/login. `login` is a username or email.
func login(login_name: String, password: String) -> ApiResult:
	var body := {"login": login_name.strip_edges(), "password": password}
	var result := await _send(HTTPClient.METHOD_POST, "auth/login", body, false)
	return _store_auth(result)


## POST /auth/logout. Session is cleared whatever the server answers.
func logout() -> ApiResult:
	var result := await _send(HTTPClient.METHOD_POST, "auth/logout", {}, true)
	Session.clear()
	return result


## GET /me. On success Session.account is refreshed.
func me() -> ApiResult:
	var result := await _send(HTTPClient.METHOD_GET, "me", {}, true)
	if result.ok:
		Session.account = ApiCodec.extract_object(result.data, "account")
	return result


# --- Characters -------------------------------------------------------------


## GET /characters. Use ApiCodec.extract_list(result.data, "characters").
func list_characters() -> ApiResult:
	return await _send(HTTPClient.METHOD_GET, "characters", {}, true)


## POST /characters. Class is always warrior in the MVP (server-side).
func create_character(character_name: String, birth_sign: String) -> ApiResult:
	var body := {"name": character_name.strip_edges(), "birth_sign": birth_sign}
	return await _send(HTTPClient.METHOD_POST, "characters", body, true)


## GET /characters/{id}.
func get_character(character_id: int) -> ApiResult:
	return await _send(HTTPClient.METHOD_GET, ApiCodec.character_path(character_id), {}, true)


## DELETE /characters/{id}.
func delete_character(character_id: int) -> ApiResult:
	return await _send(HTTPClient.METHOD_DELETE, ApiCodec.character_path(character_id), {}, true)


# --- Internals --------------------------------------------------------------


func _send(method: HTTPClient.Method, path: String, body: Dictionary, auth: bool) -> ApiResult:
	var url := ApiCodec.build_url(Session.api_base_url, path)
	var token := Session.token if auth else ""
	var headers := ApiCodec.build_headers(token, not body.is_empty())

	var http := HTTPRequest.new()
	http.timeout = timeout_sec
	add_child(http)
	_in_flight += 1

	var result: ApiResult
	var err := http.request(url, headers, method, ApiCodec.encode_body(body))
	if err != OK:
		push_warning("ApiClient: cannot start request to %s (error %d)" % [url, err])
		result = ApiResult.failure(0, ApiCodec.MSG_NETWORK)
	else:
		# request_completed(result, response_code, headers, body)
		var response: Array = await http.request_completed
		result = ApiCodec.parse_response(response[0], response[1], response[3])

	_in_flight -= 1
	http.queue_free()

	if auth and result.is_unauthorized():
		Session.clear()
		unauthorized.emit()
	return result


## Saves token + account from a login/register response into Session.
func _store_auth(result: ApiResult) -> ApiResult:
	if not result.ok:
		return result
	var token := str(result.data.get("token", ""))
	if token == "":
		return ApiResult.failure(result.status, ApiCodec.MSG_BAD_RESPONSE, result.data)
	Session.token = token
	Session.account = ApiCodec.extract_object(result.data, "account")
	Session.offline = false
	return result


## Evaluates a JS expression on web and returns it as a String ("" for null).
static func _js_string(expression: String) -> String:
	var value: Variant = JavaScriptBridge.eval(expression, true)
	return "" if value == null else str(value)
