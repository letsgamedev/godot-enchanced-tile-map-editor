extends "_base.gd"

func _init(editor: EditorPlugin, button_group: ButtonGroup).(editor) -> void:
	control = _create_button(
		button_group,
		"Rectangle",
		preload("../../icons/paint_tool_rectangle.svg"),
		KEY_U)
