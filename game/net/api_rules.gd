class_name ApiRules
extends RefCounted
## Client-side copies of the backend validation rules (docs/api.md), so forms
## can show errors before a round trip. The server stays the authority.
## Each validator returns "" when the value is fine, else a message.

const USERNAME_MIN := 3
const USERNAME_MAX := 20
const PASSWORD_MIN := 8
const CHARACTER_NAME_MIN := 3
const CHARACTER_NAME_MAX := 16
const MAX_CHARACTERS := 3
const CHARACTER_CLASS := "warrior"


static func validate_username(username: String) -> String:
	var value := username.strip_edges()
	if value.length() < USERNAME_MIN or value.length() > USERNAME_MAX:
		return "Username must be %d-%d characters." % [USERNAME_MIN, USERNAME_MAX]
	if not _matches("^[A-Za-z0-9_]+$", value):
		return "Use only letters, digits and underscores."
	return ""


static func validate_email(email: String) -> String:
	var value := email.strip_edges()
	if value == "":
		return "Email is required."
	if not _matches("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", value):
		return "Enter a valid email address."
	return ""


static func validate_password(password: String) -> String:
	if password.length() < PASSWORD_MIN:
		return "Password must be at least %d characters." % PASSWORD_MIN
	return ""


static func validate_password_confirmation(password: String, confirmation: String) -> String:
	if password != confirmation:
		return "Passwords don't match."
	return ""


static func validate_character_name(character_name: String) -> String:
	var value := character_name.strip_edges()
	if value.length() < CHARACTER_NAME_MIN or value.length() > CHARACTER_NAME_MAX:
		return "Name must be %d-%d characters." % [CHARACTER_NAME_MIN, CHARACTER_NAME_MAX]
	if not _matches("^[A-Za-z0-9]+$", value):
		return "Use only letters and digits."
	return ""


## Field errors for the login form, keyed like the API fields.
static func validate_login_form(login: String, password: String) -> Dictionary:
	var errors: Dictionary = {}
	if login.strip_edges() == "":
		errors["login"] = "Enter your username or email."
	if password == "":
		errors["password"] = "Enter your password."
	return errors


## Field errors for the register form, keyed like the API fields.
static func validate_register_form(
	username: String, email: String, password: String, confirmation: String
) -> Dictionary:
	var errors: Dictionary = {}
	_put(errors, "username", validate_username(username))
	_put(errors, "email", validate_email(email))
	_put(errors, "password", validate_password(password))
	_put(errors, "password_confirmation", validate_password_confirmation(password, confirmation))
	return errors


## Field errors for the character create form. `known_signs` are the sign ids
## from data/zodiac_signs.json (empty = don't check the id).
static func validate_character_form(
	character_name: String, birth_sign: String, known_signs: Array = []
) -> Dictionary:
	var errors: Dictionary = {}
	_put(errors, "name", validate_character_name(character_name))
	if birth_sign == "":
		errors["birth_sign"] = "Pick a birth sign."
	elif not known_signs.is_empty() and not (birth_sign in known_signs):
		errors["birth_sign"] = "Unknown birth sign."
	return errors


static func _put(errors: Dictionary, field: String, message: String) -> void:
	if message != "":
		errors[field] = message


static func _matches(pattern: String, value: String) -> bool:
	var regex := RegEx.create_from_string(pattern)
	return regex.search(value) != null
