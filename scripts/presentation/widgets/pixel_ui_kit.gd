## pixel_ui_kit.gd —— FullHaul 表现层：统一扁平卡通 UI 管线（视觉升级 V1）
##
## 职责：
##   让全部页面控件（属性栏/格阵/快捷按钮/弹窗）共用同一条平滑卡通管线：
##   原生 StyleBoxFlat（圆角面板 + 描边 + 柔和落影）直接构建控件样式，
##   图标为高分程序化绘制（96×96 画布，随 LINEAR 过滤自然抗锯齿）。
##
## 兼容说明：
##   类名沿用 PixelUiKit、方法签名与旧版一一对应（调用方零改动迁移）；
##   PX 常量保留作为「虚拟尺寸单位」（circle_button_size 的换算基准），
##   不再代表像素颗粒度。调色板对齐仓库概念图（钢蓝/奶油白/警示黄）。
##
## 设计要点：
##   - 样式按参数缓存（static），返回副本以允许调用方安全微调。
##   - 凸台感由落影营造（上亮面板 + 下坠阴影），内嵌格用深一档底色 + 细边。
##   - 文字直接使用按钮自身 Label（全局已设默认中文字体，无需子标签补丁）。

extends RefCounted
class_name PixelUiKit

## 虚拟尺寸单位：圆形按钮的入参直径以此为倍率（历史布局契约，勿随意改）
const PX := 6

# ---- 共享调色板（对齐仓库概念图：钢蓝框架 / 奶油面板 / 警示黄点缀）----
const COL_PANEL := Color(0.973, 0.945, 0.882)
const COL_BORDER := Color(0.231, 0.404, 0.784)
const COL_CHIP_BG := Color(0.937, 0.902, 0.827)
const COL_TEXT := Color(0.165, 0.2, 0.282)
const COL_TEXT_DIM := Color(0.42, 0.467, 0.573)
## 暗底亮字（主页顶条等直接压在深色页面背景上的文字）
const COL_TEXT_BRIGHT := Color(0.96, 0.945, 0.9)
const COL_GOLD := Color(0.957, 0.753, 0.267)
const COL_RED := Color(0.82, 0.333, 0.302)
const COL_RED_BORDER := Color(0.56, 0.208, 0.184)
const COL_CELL_BG := Color(0.925, 0.894, 0.82)
const COL_CELL_BORDER := Color(0.616, 0.671, 0.784)
const COL_SAFE_BG := Color(0.961, 0.898, 0.882)
const COL_SAFE_BORDER := Color(0.757, 0.325, 0.302)
const COL_ROW_BG := Color(0.945, 0.906, 0.827)

## 品质色（物品揭晓/背包格/仓库色条共用；epic 为红色系系有意决策）
const RARITY_COLORS := {
	"common": Color(0.58, 0.62, 0.70),
	"uncommon": Color(0.29, 0.69, 0.54),
	"rare": Color(0.38, 0.60, 0.90),
	"epic": Color(0.95, 0.42, 0.40),
	"legendary": Color(0.95, 0.78, 0.32),
}

static var _cache: Dictionary = {}


## 矩形按钮（圆角凸台；pressed 加深并以阴影收紧模拟下沉）。
static func style_rect_button(btn: Button, fill: Color, border: Color,
		font_size: int, font_color: Color) -> void:
	btn.add_theme_stylebox_override("normal", frame_stylebox(fill, border))
	btn.add_theme_stylebox_override("hover", frame_stylebox(fill.lightened(0.06), border.lightened(0.08)))
	btn.add_theme_stylebox_override("pressed", frame_stylebox(fill.darkened(0.10), border.darkened(0.10)))
	btn.add_theme_stylebox_override("disabled", frame_stylebox(fill.darkened(0.28), border.darkened(0.30)))
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	_style_button_font(btn, font_size, font_color)


## 圆形按钮（整圆凸台，直径 = d_virtual × PX，保持历史布局尺寸不变）。
static func style_circle_button(btn: Button, d_virtual: int, fill: Color, border: Color,
		font_size: int, font_color: Color) -> void:
	var side := circle_button_size(d_virtual)
	btn.custom_minimum_size = Vector2(side, side)
	btn.add_theme_stylebox_override("normal", circle_stylebox(d_virtual, fill, border, false))
	btn.add_theme_stylebox_override("hover", circle_stylebox(d_virtual, fill.lightened(0.06), border.lightened(0.08), false))
	btn.add_theme_stylebox_override("pressed", circle_stylebox(d_virtual, fill.darkened(0.12), border.darkened(0.12), true))
	btn.add_theme_stylebox_override("disabled", circle_stylebox(d_virtual, fill.darkened(0.32), border.darkened(0.35), true))
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	_style_button_font(btn, font_size, font_color)


static func _style_button_font(btn: Button, font_size: int, font_color: Color) -> void:
	for color_key in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color"]:
		btn.add_theme_color_override(color_key, font_color)
	btn.add_theme_font_size_override("font_size", font_size)


## 内嵌小格（背包格/安全箱格/物品格）。
static func cell(is_safe: bool, size: float) -> Panel:
	var cell := Panel.new()
	cell.custom_minimum_size = Vector2(size, size)
	if is_safe:
		cell.add_theme_stylebox_override("panel", inset_stylebox(COL_SAFE_BG, COL_SAFE_BORDER))
	else:
		cell.add_theme_stylebox_override("panel", inset_stylebox(COL_CELL_BG, COL_CELL_BORDER))
	return cell


## 品质色内嵌格（揭晓物品/背包格物品占用态）。
static func rarity_cell(rarity: String, size: float) -> Panel:
	var cell := Panel.new()
	cell.custom_minimum_size = Vector2(size, size)
	var c: Color = RARITY_COLORS.get(rarity, COL_TEXT_DIM)
	cell.add_theme_stylebox_override("panel", inset_stylebox(c.darkened(0.55), c))
	return cell


## 圆形按钮应使用的控件边长（design px）。
static func circle_button_size(d_virtual: int) -> float:
	return d_virtual * float(PX)


## 凸台圆角面板（属性栏/面板/按钮底板）：奶油/彩色填充 + 钢蓝描边 + 落影。
static func frame_stylebox(fill: Color, border: Color) -> StyleBoxFlat:
	return _flat(_key(["frame", fill, border]), fill, border, 14, true)


## 内嵌格子框架（背包/安全箱格）：无落影、细边、弱圆角，呈凹陷平板感。
static func inset_stylebox(fill: Color, border: Color) -> StyleBoxFlat:
	return _flat(_key(["inset", fill, border]), fill, border, 10, false)


## 圆形按钮框架；pressed 以加深 + 无落影表达按压下沉。
static func circle_stylebox(d_virtual: int, fill: Color, border: Color, pressed := false) -> StyleBoxFlat:
	var side := int(circle_button_size(d_virtual))
	var sb := _flat(_key(["circle", side, fill, border, pressed]), fill, border,
			side / 2 - 3, not pressed)
	sb.set_border_width_all(4)
	return sb


static func _flat(key: String, fill: Color, border: Color, radius: int, shadowed: bool) -> StyleBoxFlat:
	if not _cache.has(key):
		var sb := StyleBoxFlat.new()
		sb.bg_color = fill
		sb.set_corner_radius_all(maxi(radius, 2))
		sb.set_border_width_all(3)
		sb.border_color = border
		if shadowed:
			sb.shadow_color = Color(0.07, 0.10, 0.17, 0.18)
			sb.shadow_size = 5
			sb.shadow_offset = Vector2(0, 3)
		_cache[key] = sb
	return (_cache[key] as StyleBoxFlat).duplicate()


static func _key(parts: Array) -> String:
	var out := ""
	for p in parts:
		out += str(p) + "|"
	return out


## ---- HUD 图标（高分程序化卡通绘制，显示端 LINEAR 缩小自然抗锯齿）----

## HUD 卡通图标：coin 货币 / heart 生命 / bubble 氧气 / crate 仓库 /
## backpack 背包 / hourglass 局内计时。画布 96×96，光源统一左上。
static func icon_texture(kind: String) -> ImageTexture:
	var key := "icon|" + kind
	if _cache.has(key):
		return _cache[key]
	var img := PixelArtKit.canvas(96, 96)
	match kind:
		"coin":
			_draw_coin(img)
		"heart":
			_draw_heart(img)
		"bubble":
			_draw_bubble(img)
		"crate":
			_draw_crate(img)
		"backpack":
			_draw_backpack(img)
		"hourglass":
			_draw_hourglass(img)
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex


static func _draw_coin(img: Image) -> void:
	var gold := Color(0.957, 0.753, 0.267)
	var rim := Color(0.72, 0.53, 0.13)
	var hi := Color(0.99, 0.9, 0.62)
	PixelArtKit.ellipse(img, 48, 51, 33, 31, rim)
	PixelArtKit.ellipse(img, 46, 47, 31, 29, gold)
	PixelArtKit.ellipse(img, 46, 47, 23, 21, rim)
	PixelArtKit.ellipse(img, 46, 47, 21, 19, gold.lightened(0.08))
	PixelArtKit.vline(img, 41, 40, 54, rim)
	PixelArtKit.hline(img, 35, 57, 41, rim)
	PixelArtKit.hline(img, 37, 45, 49, rim)
	PixelArtKit.hline(img, 37, 45, 55, rim)
	PixelArtKit.line(img, 57, 38, 66, 27, hi)
	PixelArtKit.line(img, 60, 43, 70, 33, hi)


static func _draw_heart(img: Image) -> void:
	var red := Color(0.86, 0.32, 0.29)
	var dark := Color(0.62, 0.18, 0.17)
	var hi := Color(0.99, 0.62, 0.58)
	for y in range(20, 56):
		_paint_circle_row(img, 33, 37, 17, y, red)
		_paint_circle_row(img, 63, 37, 17, y, red)
	for y in range(42, 88):
		var t := float(y - 42) / 46.0
		var half := int(round(31.0 * pow(maxf(1.0 - t, 0.0), 0.68)))
		if half > 0:
			PixelArtKit.hline(img, 48 - half, 48 + half, y, red)
	PixelArtKit.ellipse(img, 31, 32, 7, 5, hi)
	PixelArtKit.px(img, 43, 26, hi)
	PixelArtKit.px(img, 44, 25, hi)


## 只绘制圆在指定行的弦段（两圆并集需各自成段，不能取单一中心半宽）。
static func _paint_circle_row(img: Image, cx: int, cy: int, r: int, y: int, c: Color) -> void:
	var dy := y - cy
	var t := 1.0 - float(dy * dy) / float(r * r)
	if t <= 0.0:
		return
	var half := int(round(float(r) * sqrt(t)))
	PixelArtKit.hline(img, cx - half, cx + half, y, c)


static func _draw_bubble(img: Image) -> void:
	var deep := Color(0.16, 0.52, 0.66)
	var body := Color(0.36, 0.78, 0.88)
	var pale := Color(0.85, 0.97, 1.0)
	PixelArtKit.ellipse(img, 45, 51, 30, 28, deep)
	PixelArtKit.ellipse(img, 44, 49, 28, 26, body)
	PixelArtKit.ellipse(img, 34, 38, 9, 6, pale)
	PixelArtKit.ellipse(img, 68, 76, 9, 8, body)
	PixelArtKit.ellipse(img, 68, 76, 7, 6, Color(0.55, 0.87, 0.93))
	PixelArtKit.px(img, 72, 30, pale)
	PixelArtKit.px(img, 79, 37, pale)
	PixelArtKit.px(img, 26, 62, Color(0.6, 0.9, 0.96))


static func _draw_crate(img: Image) -> void:
	var wood := Color(0.808, 0.588, 0.333)
	var wood_light := Color(0.883, 0.678, 0.412)
	var edge := Color(0.44, 0.28, 0.14)
	PixelArtKit.rect(img, 12, 20, 72, 60, edge)
	PixelArtKit.rect(img, 16, 24, 64, 52, wood)
	PixelArtKit.rect(img, 16, 24, 64, 8, wood_light)
	PixelArtKit.hline(img, 16, 79, 50, edge.darkened(0.12))
	PixelArtKit.line(img, 16, 76, 44, 24, edge)
	PixelArtKit.line(img, 44, 76, 80, 24, edge.lightened(0.18))
	for p in [Vector2i(14, 22), Vector2i(81, 22), Vector2i(14, 77), Vector2i(81, 77)]:
		PixelArtKit.px(img, p.x, p.y, edge.darkened(0.25))


static func _draw_backpack(img: Image) -> void:
	var olive := Color(0.42, 0.55, 0.30)
	var olive_dk := Color(0.30, 0.41, 0.21)
	var gold := Color(0.957, 0.753, 0.267)
	var dark := Color(0.22, 0.28, 0.16)
	## 背带提手：拱形（两侧立柱 + 顶横梁）
	PixelArtKit.rect(img, 32, 14, 6, 18, dark)
	PixelArtKit.rect(img, 58, 14, 6, 18, dark)
	PixelArtKit.rect(img, 32, 10, 32, 6, dark)
	PixelArtKit.rect(img, 14, 26, 68, 60, dark)
	PixelArtKit.rect(img, 18, 30, 60, 52, olive)
	PixelArtKit.rect(img, 18, 30, 60, 20, olive_dk)
	PixelArtKit.hline(img, 18, 77, 54, dark)
	PixelArtKit.rect(img, 40, 56, 16, 22, olive_dk)
	PixelArtKit.rect(img, 44, 58, 8, 12, gold)
	PixelArtKit.px(img, 47, 63, dark)


static func _draw_hourglass(img: Image) -> void:
	var frame := Color(0.231, 0.404, 0.784)
	var sand := Color(0.957, 0.753, 0.267)
	var sand_hi := Color(0.99, 0.87, 0.55)
	PixelArtKit.rect(img, 20, 12, 56, 8, frame)
	PixelArtKit.rect(img, 20, 76, 56, 8, frame)
	PixelArtKit.line(img, 26, 20, 44, 48, frame)
	PixelArtKit.line(img, 70, 20, 52, 48, frame)
	PixelArtKit.line(img, 26, 76, 44, 48, frame)
	PixelArtKit.line(img, 70, 76, 52, 48, frame)
	## 上腔残沙（顶宽收向颈部）
	for i in range(0, 18):
		var y := 24 + i
		var half := int(round(16.0 - 12.0 * float(i) / 17.0))
		PixelArtKit.hline(img, 48 - half, 48 + half, y, sand)
	## 下落沙流 + 底部沙堆
	PixelArtKit.vline(img, 48, 46, 64, sand)
	for i in range(0, 14):
		var half := int(round(4.0 + 16.0 * float(i) / 13.0))
		PixelArtKit.hline(img, 48 - half, 48 + half, 72 - i, sand)
	PixelArtKit.px(img, 46, 28, sand_hi)
	PixelArtKit.px(img, 50, 68, sand_hi)
