## model_preview_popup.gd —— FullHaul 表现层：物品 3D 大图查看弹窗（视觉升级 V1）
##
## 职责：
##   基于 PopupBase 骨架组装「360° 自转大图 + 名称/品质/价值」查看弹窗，
##   局外仓库行与局内背包格共用。每次 create 重建一份，由调用方持有引用
##   并 add_child 后 open()。

extends RefCounted
class_name ModelPreviewPopup

## 弹窗与视口尺寸（design px）
const PANEL_SIZE := Vector2(860, 1040)
const VIEW_SIZE := 720.0


## 组装一份大图弹窗；info 为各页 _item_info 产出的展示字典
## （definition_id / name / rarity / value）。占位正方体随品质着色。
## on_sell 提供时（仓库物品）内容区底部追加「出售」按钮：点击回调后关弹窗，
## 出售结果由调用方经事件总线刷新。
static func create(info: Dictionary, on_sell: Callable = Callable()) -> PopupBase:
	var display_name := str(info.get("name", ""))
	var popup := PopupBase.create(PANEL_SIZE, display_name, true)
	var rarity_color: Color = PixelUiKit.RARITY_COLORS.get(str(info.get("rarity", "")), PixelUiKit.COL_TEXT_DIM)
	var view := ModelPreviewView.create(str(info.get("definition_id", "")), VIEW_SIZE, true, rarity_color)
	view.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	popup.content.add_child(view)
	var subtitle := Label.new()
	subtitle.text = "品质 %s · 价值 %d" % [str(info.get("rarity", "")), int(info.get("value", 0))]
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_color_override("font_color", PixelUiKit.COL_TEXT_DIM)
	subtitle.add_theme_font_size_override("font_size", 28)
	popup.content.add_child(subtitle)
	if on_sell.is_valid():
		var sell := Button.new()
		sell.text = "出售"
		sell.custom_minimum_size = Vector2(0, 92)
		PixelUiKit.style_rect_button(sell, PixelUiKit.COL_RED, PixelUiKit.COL_RED_BORDER,
				30, Color(1, 0.96, 0.94))
		sell.pressed.connect(func():
			on_sell.call()
			popup.close())
		popup.content.add_child(sell)
	return popup
