extends RefCounted
## Shared Theme for the login flow, built in code (no binary assets).
## Dark navy + gold accent, matching icon.svg. Usage:
##     const LoginTheme := preload("res://ui/login/login_theme.gd")
##     theme = LoginTheme.build()
## Type variations: TitleLabel, SubtitleLabel, MutedLabel, ErrorLabel,
## AccentButton, DangerButton, SignCard (Button), Card (PanelContainer).

const NAVY := Color("#1d2440")
const NAVY_DARK := Color("#121830")
const PANEL := Color("#232c4d")
const PANEL_LIGHT := Color("#2d3860")
const BORDER := Color("#3a4670")
const GOLD := Color("#f4c542")
const GOLD_DARK := Color("#c99a1e")
const TEXT := Color("#ece8dc")
const MUTED := Color("#9aa3c0")
const ERROR := Color("#ff7a7a")
const DANGER := Color("#b8434e")
const SUCCESS := Color("#7fd18b")

const ELEMENT_COLORS := {
	"fire": Color("#ff8a50"),
	"earth": Color("#b9cf6a"),
	"air": Color("#bcd3f2"),
	"water": Color("#5fb4ff"),
}


static func build() -> Theme:
	var theme := Theme.new()
	theme.default_font_size = 16
	_add_panels(theme)
	_add_labels(theme)
	_add_buttons(theme)
	_add_line_edit(theme)
	_add_tabs(theme)
	_add_misc(theme)
	return theme


static func element_color(element: String) -> Color:
	return ELEMENT_COLORS.get(element, MUTED)


## Flat style box with uniform border, corner radius and content margin.
static func box(
	bg: Color, border: Color = Color.TRANSPARENT, border_width: int = 0,
	radius: int = 6, margin: float = 8.0
) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(radius)
	style.set_content_margin_all(margin)
	style.anti_aliasing = true
	return style


static func _add_panels(theme: Theme) -> void:
	var main_panel := box(PANEL, BORDER, 1, 12, 28)
	main_panel.shadow_color = Color(0, 0, 0, 0.45)
	main_panel.shadow_size = 18
	theme.set_stylebox("panel", "PanelContainer", main_panel)
	theme.set_stylebox("panel", "Panel", box(PANEL, BORDER, 1, 12, 0))

	theme.set_type_variation("Card", "PanelContainer")
	theme.set_stylebox("panel", "Card", box(PANEL_LIGHT, BORDER, 1, 8, 14))


static func _add_labels(theme: Theme) -> void:
	theme.set_color("font_color", "Label", TEXT)

	theme.set_type_variation("TitleLabel", "Label")
	theme.set_color("font_color", "TitleLabel", GOLD)
	theme.set_color("font_shadow_color", "TitleLabel", Color(0, 0, 0, 0.6))
	theme.set_constant("shadow_offset_x", "TitleLabel", 0)
	theme.set_constant("shadow_offset_y", "TitleLabel", 3)
	theme.set_font_size("font_size", "TitleLabel", 40)

	theme.set_type_variation("SubtitleLabel", "Label")
	theme.set_color("font_color", "SubtitleLabel", GOLD)
	theme.set_font_size("font_size", "SubtitleLabel", 22)

	theme.set_type_variation("MutedLabel", "Label")
	theme.set_color("font_color", "MutedLabel", MUTED)
	theme.set_font_size("font_size", "MutedLabel", 14)

	theme.set_type_variation("ErrorLabel", "Label")
	theme.set_color("font_color", "ErrorLabel", ERROR)
	theme.set_font_size("font_size", "ErrorLabel", 13)


static func _add_buttons(theme: Theme) -> void:
	_style_button(theme, "Button", PANEL_LIGHT, BORDER, TEXT)
	theme.set_type_variation("AccentButton", "Button")
	_style_button(theme, "AccentButton", GOLD, GOLD_DARK, NAVY_DARK)
	theme.set_type_variation("DangerButton", "Button")
	_style_button(theme, "DangerButton", DANGER, DANGER.darkened(0.3), TEXT)

	# Toggle cards for the birth sign picker: gold border when selected.
	theme.set_type_variation("SignCard", "Button")
	_style_button(theme, "SignCard", PANEL_LIGHT, BORDER, TEXT)
	theme.set_stylebox("pressed", "SignCard", box(PANEL_LIGHT.lightened(0.08), GOLD, 3, 8, 10))
	theme.set_stylebox("hover_pressed", "SignCard", box(PANEL_LIGHT.lightened(0.12), GOLD, 3, 8, 10))


static func _style_button(
	theme: Theme, type_name: String, bg: Color, border: Color, font: Color
) -> void:
	theme.set_stylebox("normal", type_name, box(bg, border, 1, 6, 10))
	theme.set_stylebox("hover", type_name, box(bg.lightened(0.1), GOLD, 1, 6, 10))
	theme.set_stylebox("pressed", type_name, box(bg.darkened(0.15), GOLD, 1, 6, 10))
	theme.set_stylebox("disabled", type_name, box(bg.darkened(0.35), border.darkened(0.3), 1, 6, 10))
	var focus := box(Color.TRANSPARENT, GOLD, 2, 6, 10)
	focus.draw_center = false
	theme.set_stylebox("focus", type_name, focus)
	theme.set_color("font_color", type_name, font)
	theme.set_color("font_hover_color", type_name, font)
	theme.set_color("font_pressed_color", type_name, font)
	theme.set_color("font_hover_pressed_color", type_name, font)
	theme.set_color("font_focus_color", type_name, font)
	theme.set_color("font_disabled_color", type_name, Color(font, 0.45))


static func _add_line_edit(theme: Theme) -> void:
	theme.set_stylebox("normal", "LineEdit", box(NAVY_DARK, BORDER, 1, 6, 10))
	theme.set_stylebox("focus", "LineEdit", box(Color.TRANSPARENT, GOLD, 2, 6, 10))
	theme.set_stylebox("read_only", "LineEdit", box(NAVY_DARK.darkened(0.2), BORDER, 1, 6, 10))
	theme.set_color("font_color", "LineEdit", TEXT)
	theme.set_color("font_placeholder_color", "LineEdit", Color(MUTED, 0.7))
	theme.set_color("caret_color", "LineEdit", GOLD)
	theme.set_color("selection_color", "LineEdit", Color(GOLD, 0.35))


static func _add_tabs(theme: Theme) -> void:
	theme.set_stylebox("panel", "TabContainer", box(Color.TRANSPARENT, Color.TRANSPARENT, 0, 0, 0))
	var selected := box(PANEL, GOLD, 0, 6, 10)
	selected.border_width_bottom = 3
	theme.set_stylebox("tab_selected", "TabContainer", selected)
	theme.set_stylebox("tab_unselected", "TabContainer", box(PANEL, BORDER, 0, 6, 10))
	var hovered := box(PANEL_LIGHT, BORDER, 0, 6, 10)
	hovered.border_width_bottom = 1
	theme.set_stylebox("tab_hovered", "TabContainer", hovered)
	theme.set_stylebox("tabbar_background", "TabContainer", box(Color.TRANSPARENT, BORDER, 0, 0, 0))
	theme.set_color("font_selected_color", "TabContainer", GOLD)
	theme.set_color("font_unselected_color", "TabContainer", MUTED)
	theme.set_color("font_hovered_color", "TabContainer", TEXT)
	theme.set_font_size("font_size", "TabContainer", 18)


static func _add_misc(theme: Theme) -> void:
	theme.set_stylebox("panel", "AcceptDialog", box(PANEL, BORDER, 1, 0, 16))
	theme.set_stylebox("panel", "ConfirmationDialog", box(PANEL, BORDER, 1, 0, 16))
	theme.set_color("title_color", "Window", GOLD)
	theme.set_stylebox("embedded_border", "Window", box(PANEL, GOLD_DARK, 2, 8, 0))
	theme.set_stylebox("embedded_unfocused_border", "Window", box(PANEL, BORDER, 2, 8, 0))
	var scroll := box(Color(BORDER, 0.5), Color.TRANSPARENT, 0, 4, 0)
	theme.set_stylebox("scroll", "VScrollBar", box(Color(NAVY_DARK, 0.5), Color.TRANSPARENT, 0, 4, 2))
	theme.set_stylebox("grabber", "VScrollBar", scroll)
	theme.set_stylebox("grabber_highlight", "VScrollBar", box(GOLD_DARK, Color.TRANSPARENT, 0, 4, 0))
	theme.set_stylebox("grabber_pressed", "VScrollBar", box(GOLD, Color.TRANSPARENT, 0, 4, 0))
	var line := StyleBoxLine.new()
	line.color = BORDER
	line.thickness = 1
	theme.set_stylebox("separator", "HSeparator", line)
	theme.set_constant("separation", "HSeparator", 12)
