## popup_base.gd —— FullHaul 表现层：统一全屏遮罩弹窗骨架（视觉升级 V1）
##
## 职责：
##   收敛此前各页手搓的「全屏 Control + Dim + Center + PanelContainer」
##   同构三连结构：半透明遮罩 + 居中圆角凸台面板（PixelUiKit 单一来源）+
##   统一边距的内容区（可选标题/内建关闭钮）。内容由使用方挂到 content，
##   节点引用自行保存；开关走 open()/close()。

extends Control
class_name PopupBase

## 内建关闭按钮触发；外部直接置 visible 不会发此信号
signal closed

var panel: PanelContainer
var content: VBoxContainer
var title_label: Label = null


## 组装一份标准弹窗。panel_min 为面板最小尺寸（design px）；
## title 非空时置于内容区顶部；with_close 时在内容区底部追加内建关闭钮。
static func create(panel_min: Vector2, title := "", with_close := false) -> PopupBase:
	var popup := PopupBase.new()
	popup.visible = false
	popup.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.05, 0.09, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	popup.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	popup.add_child(center)

	var margin := MarginContainer.new()
	for pair in [["margin_left", 28], ["margin_top", 24], ["margin_right", 28], ["margin_bottom", 24]]:
		margin.add_theme_constant_override(pair[0], pair[1])

	popup.panel = PanelContainer.new()
	popup.panel.custom_minimum_size = panel_min
	popup.panel.add_theme_stylebox_override("panel",
			PixelUiKit.frame_stylebox(PixelUiKit.COL_PANEL, PixelUiKit.COL_BORDER))
	popup.panel.add_child(margin)
	center.add_child(popup.panel)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 18)
	margin.add_child(outer)

	if title != "":
		popup.title_label = Label.new()
		popup.title_label.text = title
		popup.title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		popup.title_label.add_theme_color_override("font_color", PixelUiKit.COL_TEXT)
		popup.title_label.add_theme_font_size_override("font_size", 34)
		outer.add_child(popup.title_label)

	popup.content = VBoxContainer.new()
	popup.content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	popup.content.add_theme_constant_override("separation", 16)
	outer.add_child(popup.content)

	if with_close:
		var close_btn := Button.new()
		close_btn.text = "关闭"
		close_btn.custom_minimum_size = Vector2(0, 92)
		PixelUiKit.style_rect_button(close_btn, PixelUiKit.COL_CHIP_BG,
				PixelUiKit.COL_BORDER, 30, PixelUiKit.COL_TEXT)
		close_btn.pressed.connect(func(): popup.close())
		outer.add_child(close_btn)
	return popup


func open() -> void:
	visible = true


func close() -> void:
	if not visible:
		return
	visible = false
	closed.emit()
