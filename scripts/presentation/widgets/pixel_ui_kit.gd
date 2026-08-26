## pixel_ui_kit.gd —— FullHaul 表现层：统一像素 UI 管线（WORD-40 首页视觉）
##
## 职责：
##   让首页 UI 控件（属性栏/格阵/快捷按钮/弹窗）与 2.5D 基地共用同一条
##   像素化管线：低分辨率画布绘制控件框架 -> PixelArtKit.magnify 整倍
##   最近邻放大 -> ImageTexture -> StyleBoxTexture（矩形 9-slice / 圆形整图）。
##   使用方控件需设置 texture_filter = NEAREST 以保持颗粒锐利。
##
## 设计要点：
##   - 纹理按参数自动缓存（static），同款式全局只生成一次。
##   - 矩形框架虚拟 12×12（1px 切角外框 + 1px 受光/落影倒角）；9-slice 的
##     texture_margin = 颗粒度 PX，边框在任意控件尺寸下粗细保持一致。
##   - 圆形按钮不走 9-slice 拉伸，按 d_virtual × PX 1:1 铺放（控件尺寸用
##     circle_button_size() 设定），保证像素均匀。

extends RefCounted
class_name PixelUiKit

## 像素颗粒：虚拟像素放大倍率（与 BaseView.PIXEL_SCALE 对齐）
const PX := 6

# ---- 共享调色板（首页/局内统一像素风）----
const COL_PANEL := Color(0.125, 0.149, 0.204)
const COL_BORDER := Color(0.227, 0.259, 0.341)
const COL_CHIP_BG := Color(0.149, 0.176, 0.239)
const COL_TEXT := Color(0.91, 0.925, 0.957)
const COL_TEXT_DIM := Color(0.604, 0.647, 0.741)
const COL_GOLD := Color(0.949, 0.757, 0.306)
const COL_RED := Color(0.788, 0.31, 0.275)
const COL_RED_BORDER := Color(1.0, 0.565, 0.525)
const COL_CELL_BG := Color(0.102, 0.122, 0.169)
const COL_CELL_BORDER := Color(0.235, 0.267, 0.349)
const COL_SAFE_BG := Color(0.169, 0.102, 0.118)
const COL_SAFE_BORDER := Color(0.69, 0.283, 0.239)
const COL_ROW_BG := Color(0.114, 0.137, 0.188)

## 品质色（物品揭晓/背包格/仓库色条共用）
const RARITY_COLORS := {
	"common": Color(0.58, 0.62, 0.70),
	"uncommon": Color(0.42, 0.72, 0.38),
	"rare": Color(0.38, 0.60, 0.90),
	"epic": Color(0.95, 0.42, 0.40),
	"legendary": Color(0.95, 0.78, 0.32),
}

static var _cache: Dictionary = {}


## 矩形像素按钮（凸台框架 9-slice；文字改由线性过滤的子标签承载保持平滑）。
static func style_rect_button(btn: Button, fill: Color, border: Color,
		font_size: int, font_color: Color) -> void:
	btn.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	btn.add_theme_stylebox_override("normal", frame_stylebox(fill, border))
	btn.add_theme_stylebox_override("hover", frame_stylebox(fill.lightened(0.05), border.lightened(0.08)))
	btn.add_theme_stylebox_override("pressed", frame_stylebox(fill.darkened(0.08), border.darkened(0.1)))
	btn.add_theme_stylebox_override("disabled", frame_stylebox(fill.darkened(0.3), border.darkened(0.3)))
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	_style_button_font(btn, font_size, font_color)
	btn.add_theme_color_override("font_disabled_color", font_color.darkened(0.45))
	_swap_text_to_smooth_label(btn, font_size, font_color)


## 圆形像素按钮（整图铺放，尺寸 = 虚拟直径 × 颗粒度）。
static func style_circle_button(btn: Button, d_virtual: int, fill: Color, border: Color,
		font_size: int, font_color: Color) -> void:
	btn.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var side := circle_button_size(d_virtual)
	btn.custom_minimum_size = Vector2(side, side)
	btn.add_theme_stylebox_override("normal", circle_stylebox(d_virtual, fill, border, false))
	btn.add_theme_stylebox_override("hover", circle_stylebox(d_virtual, fill.lightened(0.05), border.lightened(0.08), false))
	btn.add_theme_stylebox_override("pressed", circle_stylebox(d_virtual, fill, border, true))
	btn.add_theme_stylebox_override("disabled", circle_stylebox(d_virtual, fill.darkened(0.35), border.darkened(0.35), false))
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	_style_button_font(btn, font_size, font_color)
	btn.add_theme_color_override("font_disabled_color", font_color.darkened(0.45))
	_swap_text_to_smooth_label(btn, font_size, font_color)


static func _style_button_font(btn: Button, font_size: int, font_color: Color) -> void:
	for color_key in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color"]:
		btn.add_theme_color_override(color_key, font_color)
	btn.add_theme_font_size_override("font_size", font_size)


## 按钮自身处于 NEAREST 过滤下，把 text 转为 LINEAR 过滤的居中子标签。
static func _swap_text_to_smooth_label(btn: Button, font_size: int, font_color: Color) -> void:
	if btn.text == "":
		return
	var label := Label.new()
	label.text = btn.text
	btn.text = ""
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", font_color)
	btn.add_child(label)


## 内嵌小格（背包格/安全箱格/物品格）。
static func cell(is_safe: bool, size: float) -> Panel:
	var cell := Panel.new()
	cell.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	cell.custom_minimum_size = Vector2(size, size)
	if is_safe:
		cell.add_theme_stylebox_override("panel", inset_stylebox(COL_SAFE_BG, COL_SAFE_BORDER))
	else:
		cell.add_theme_stylebox_override("panel", inset_stylebox(COL_CELL_BG, COL_CELL_BORDER))
	return cell


## 品质色内嵌格（揭晓物品/背包格物品占用态）。
static func rarity_cell(rarity: String, size: float) -> Panel:
	var cell := Panel.new()
	cell.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	cell.custom_minimum_size = Vector2(size, size)
	var c: Color = RARITY_COLORS.get(rarity, COL_TEXT_DIM)
	cell.add_theme_stylebox_override("panel", inset_stylebox(c.darkened(0.55), c))
	return cell


## 圆形按钮应使用的控件边长（design px）。
static func circle_button_size(d_virtual: int) -> float:
	return d_virtual * float(PX)


## 凸台矩形框架（属性栏/面板/按钮底板）：上左受光、下右落影。
static func frame_stylebox(fill: Color, border: Color) -> StyleBoxTexture:
	return _frame_stylebox_impl(_key([fill, border, false]), fill, border, false)


## 内嵌格子框架（背包/安全箱格）：上左内影、下右提亮。
static func inset_stylebox(fill: Color, border: Color) -> StyleBoxTexture:
	return _frame_stylebox_impl(_key([fill, border, true]), fill, border, true)


## 圆形按钮框架；pressed 为下沉按压态（整体下移 1 虚拟像素 + 变暗）。
static func circle_stylebox(d_virtual: int, fill: Color, border: Color, pressed := false) -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	sb.texture = _circle_texture(_key(["circle", d_virtual, fill, border, pressed]),
			d_virtual, fill, border, pressed)
	return sb


static func _frame_stylebox_impl(key: String, fill: Color, border: Color, inset: bool) -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	sb.texture = _frame_texture(key, fill, border, inset)
	## 9-slice 边距须盖满「外框 + 倒角」2 颗粒，拉伸中心从平坦填充区开始
	sb.texture_margin_left = 2 * PX
	sb.texture_margin_top = 2 * PX
	sb.texture_margin_right = 2 * PX
	sb.texture_margin_bottom = 2 * PX
	return sb


static func _frame_texture(key: String, fill: Color, border: Color, inset: bool) -> ImageTexture:
	if _cache.has(key):
		return _cache[key]
	var v := PixelArtKit.canvas(12, 12)
	var light := border.lightened(0.22)
	var dark := border.darkened(0.28)
	if inset:
		light = border.lightened(0.16)
		dark = fill.darkened(0.35)
	_oct(v, 0, border)
	_oct(v, 1, fill)
	if inset:
		## 内嵌：上/左压暗成内影，下/右提亮
		PixelArtKit.hline(v, 3, 8, 1, dark)
		PixelArtKit.vline(v, 1, 2, 9, dark)
		PixelArtKit.hline(v, 3, 8, 10, light)
		PixelArtKit.vline(v, 10, 2, 9, light)
	else:
		## 凸台：上/左受光，下/右落影
		PixelArtKit.hline(v, 3, 8, 1, light)
		PixelArtKit.vline(v, 1, 2, 9, light)
		PixelArtKit.hline(v, 3, 8, 10, dark)
		PixelArtKit.vline(v, 10, 2, 9, dark)
	var tex := ImageTexture.create_from_image(PixelArtKit.magnify(v, PX))
	_cache[key] = tex
	return tex


## 12×12 满幅切角八边形（inset 为向内缩的圈层；四角 1 颗粒切角，
## 中段行列均铺满画布边缘，保证 9-slice 边距外无透明像素）。
static func _oct(v: Image, inset: int, c: Color) -> void:
	PixelArtKit.hline(v, 2 + inset, 9 - inset, inset, c)
	for y in range(inset + 1, 11 - inset):
		PixelArtKit.hline(v, inset, 11 - inset, y, c)
	PixelArtKit.hline(v, 2 + inset, 9 - inset, 11 - inset, c)


static func _circle_texture(key: String, d: int, fill: Color, border: Color,
		pressed: bool) -> ImageTexture:
	if _cache.has(key):
		return _cache[key]
	var v := PixelArtKit.canvas(d, d)
	var c := d / 2
	var r := c - 1
	var sink := 1 if pressed else 0
	var body := fill.darkened(0.15) if pressed else fill
	PixelArtKit.ellipse(v, c, c + sink, r, r, border)
	PixelArtKit.ellipse(v, c, c + sink, r - 1, r - 1, body)
	## 顶部受光弧（两行）与底部落影弧（按圆方程取弦宽，限制在受光体内）
	var t := r - 3
	var hw := int(sqrt(maxf(float((r - 1) * (r - 1) - t * t), 0.0))) - 1
	if hw > 0:
		PixelArtKit.hline(v, c - hw, c + hw, c + sink - t, body.lightened(0.18))
		PixelArtKit.hline(v, c - hw + 1, c + hw - 1, c + sink - t + 1, body.lightened(0.1))
		PixelArtKit.hline(v, c - hw, c + hw, c + sink + t, body.darkened(0.18))
	var tex := ImageTexture.create_from_image(PixelArtKit.magnify(v, PX))
	_cache[key] = tex
	return tex


static func _key(parts: Array) -> String:
	var out := ""
	for p in parts:
		out += str(p) + "|"
	return out


## ---- 像素图标（HUD 用，8×8 虚拟画布 × PX）----

## 图案素材：生命（红心，p 为高光、d 为暗部）
const HEART_PATTERN := [
	".##..##.",
	"#p######",
	"########",
	"########",
	".######.",
	"..dddd..",
	"...dd...",
	"........",
]

## 图案素材：仓库（木箱）
const CRATE_PATTERN := [
	"oooooooo",
	"owwwwwwo",
	"olwwwwwo",
	"oddddddo",
	"owwwwwwo",
	"olwwwwwo",
	"owwwwwwo",
	"oooooooo",
]

## 图案素材：背包（含提手与金色扣带）
const BACKPACK_PATTERN := [
	"..dddd..",
	".oo..oo.",
	"oooooooo",
	"oggggggo",
	"oggggggo",
	"oooyyooo",
	"oggggggo",
	".oooooo.",
]

## 图案素材：沙漏（局内计时；f 框架、s 沙）
const HOURGLASS_PATTERN := [
	".ffffff.",
	".fssssf.",
	"..fssf..",
	"...ff...",
	"..f..f..",
	".f....f.",
	".ffffff.",
	"........",
]


## HUD 像素图标：coin 货币 / heart 生命 / bubble 氧气 / crate 仓库 / backpack 背包。
static func icon_texture(kind: String) -> ImageTexture:
	var key := "icon|" + kind
	if _cache.has(key):
		return _cache[key]
	var img: Image
	match kind:
		"coin":
			img = PixelArtKit.canvas(8, 8)
			PixelArtKit.ellipse(img, 4, 4, 3, 3, Color(0.44, 0.33, 0.09))
			PixelArtKit.ellipse(img, 4, 4, 2, 2, Color(0.95, 0.76, 0.31))
			PixelArtKit.hline(img, 2, 4, 2, Color(1, 0.93, 0.66))
			PixelArtKit.px(img, 4, 4, Color(0.72, 0.53, 0.13))
		"heart":
			img = _pattern_image(HEART_PATTERN, {
				"#": Color(0.85, 0.29, 0.26),
				"d": Color(0.6, 0.16, 0.16),
				"p": Color(0.99, 0.65, 0.6),
			})
		"bubble":
			img = PixelArtKit.canvas(8, 8)
			PixelArtKit.ellipse(img, 4, 4, 3, 3, Color(0.13, 0.4, 0.5))
			PixelArtKit.ellipse(img, 4, 4, 2, 2, Color(0.36, 0.78, 0.88))
			PixelArtKit.px(img, 3, 2, Color(0.85, 0.97, 1))
			PixelArtKit.px(img, 2, 3, Color(0.85, 0.97, 1))
			PixelArtKit.px(img, 7, 1, Color(0.36, 0.78, 0.88))
		"crate":
			img = _pattern_image(CRATE_PATTERN, {
				"o": Color(0.29, 0.2, 0.1),
				"w": Color(0.54, 0.35, 0.18),
				"l": Color(0.65, 0.44, 0.23),
				"d": Color(0.42, 0.27, 0.14),
			})
		"backpack":
			img = _pattern_image(BACKPACK_PATTERN, {
				"o": Color(0.24, 0.16, 0.09),
				"d": Color(0.24, 0.16, 0.09),
				"g": Color(0.42, 0.5, 0.23),
				"y": Color(0.95, 0.76, 0.31),
			})
		"hourglass":
			img = _pattern_image(HOURGLASS_PATTERN, {
				"f": Color(0.62, 0.65, 0.7),
				"s": Color(0.95, 0.76, 0.31),
			})
		_:
			img = PixelArtKit.canvas(8, 8)
	var tex := ImageTexture.create_from_image(PixelArtKit.magnify(img, PX))
	_cache[key] = tex
	return tex


## 按字符图案绘制像素图（'.' 与未映射字符为透明）。
static func _pattern_image(rows: Array, palette: Dictionary) -> Image:
	var h := rows.size()
	var w := (rows[0] as String).length()
	var img := PixelArtKit.canvas(w, h)
	for y in h:
		var line: String = rows[y]
		for x in w:
			var ch := line[x]
			if palette.has(ch):
				PixelArtKit.px(img, x, y, palette[ch])
	return img
