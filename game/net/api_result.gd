class_name ApiResult
extends RefCounted
## Outcome of one backend API call (see docs/api.md). Returned by every
## ApiClient method via `await`. Plain data, no scene or autoload dependencies.

## HTTP status code, or 0 when the request never got a response
## (network failure, timeout, bad URL).
var status: int = 0
## True for a 2xx response whose body parsed (or was empty).
var ok: bool = false
## Parsed JSON body. Empty for 204 responses and failures without a body.
var data: Dictionary = {}
## Human-readable message for the UI. Empty when `ok`.
var error_message: String = ""
## 422 validation errors: field name -> first message for that field
## (e.g. {"username": "The username has already been taken."}).
var field_errors: Dictionary = {}


static func success(status_code: int, body: Dictionary) -> ApiResult:
	var result := ApiResult.new()
	result.ok = true
	result.status = status_code
	result.data = body
	return result


static func failure(
	status_code: int, message: String, body: Dictionary = {}, fields: Dictionary = {}
) -> ApiResult:
	var result := ApiResult.new()
	result.ok = false
	result.status = status_code
	result.error_message = message
	result.data = body
	result.field_errors = fields
	return result


## True when the request never reached the server (or got no response).
func is_network_error() -> bool:
	return status == 0


func is_unauthorized() -> bool:
	return status == 401


func has_field_errors() -> bool:
	return not field_errors.is_empty()


## Field message, or "" when that field has no error.
func field_error(field: String) -> String:
	return str(field_errors.get(field, ""))


func to_dict() -> Dictionary:
	return {
		"ok": ok,
		"status": status,
		"data": data,
		"error_message": error_message,
		"field_errors": field_errors,
	}
