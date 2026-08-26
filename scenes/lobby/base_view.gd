## base_view.gd —— FullHaul 表现层：首页 2.5D 俯视像素基地（WORD-40）
##
## 职责：
##   按示意草图在首页中部呈现「2.5D 俯视角的基地」：等距 5×5 地砖平台 +
##   主屋/仓库棚/菜园/水塔/灌木/旗杆等元素；低分辨率程序化绘制后经节点
##   scale 整数倍最近邻放大，形成像素化观感；含旗帜飘动、屋顶信标两处
##   轻量动画。纯表现组件，不接事件总线、不含业务逻辑。
##
## 实现说明：
##   - 静态场景合成进单张贴图（Sprite2D），动画元素（旗面/信标光点）为
##     独立小贴图，避免逐帧重绘整幅画面。
##   - 所有坐标均为虚拟像素（画布 176×126，节点 scale=6 放大）；
##     绘制原语来自 PixelArtKit。

extends Node2D
class_name BaseView

## 虚拟画布尺寸与放大倍率（最近邻放大 → 像素颗粒感来源）
const CANVAS_W := 176
const CANVAS_H := 126
const PIXEL_SCALE := 6

## 等距参数：地砖半宽/半高（2:1）、平台边长（格）、平台顶角画布坐标
const TILE_HW := 16
const TILE_HH := 8
const PLATFORM_N := 5
const ORIGIN_X := 88
const ORIGIN_Y := 34
## 平台侧裙（土层）高度
const SKIRT_H := 10

## 石板路占用的格子（南角入口 -> 中心）
const PATH_TILES := [Vector2i(2, 2), Vector2i(3, 3), Vector2i(4, 4)]

# ---- 调色板（等距三面受光：顶亮 / 左中 / 右暗）----
const C_GRASS_A := Color(0.333, 0.564, 0.267)
const C_GRASS_B := Color(0.302, 0.522, 0.243)
const C_GRASS_C := Color(0.365, 0.60, 0.29)
const C_PATH_A := Color(0.62, 0.588, 0.482)
const C_PATH_B := Color(0.565, 0.535, 0.44)
const C_EDGE_DARK := Color(0.18, 0.31, 0.14)
const C_EDGE_LIGHT := Color(0.44, 0.68, 0.34)
const C_DIRT_L := Color(0.42, 0.298, 0.188)
const C_DIRT_R := Color(0.337, 0.235, 0.145)
const C_WALL_L := Color(0.815, 0.745, 0.578)
const C_WALL_R := Color(0.68, 0.61, 0.46)
const C_ROOF := Color(0.71, 0.373, 0.257)
const C_ROOF_D := Color(0.5, 0.245, 0.16)
const C_DOOR := Color(0.318, 0.212, 0.125)
const C_WINDOW_F := Color(0.35, 0.27, 0.16)
const C_WINDOW := Color(1.0, 0.845, 0.42)
const C_ANTENNA := Color(0.55, 0.58, 0.62)
const C_CANOPY := Color(0.78, 0.425, 0.278)
const C_CANOPY_L := Color(0.68, 0.36, 0.235)
const C_CANOPY_R := Color(0.57, 0.3, 0.195)
const C_CANOPY_SEAM := Color(0.64, 0.33, 0.21)
const C_POLE := Color(0.318, 0.231, 0.145)
const C_CRATE_T := Color(0.735, 0.56, 0.345)
const C_CRATE_L := Color(0.63, 0.47, 0.28)
const C_CRATE_R := Color(0.52, 0.385, 0.223)
const C_CRATE_O := Color(0.36, 0.26, 0.15)
const C_BARREL := Color(0.47, 0.53, 0.585)
const C_BARREL_T := Color(0.585, 0.65, 0.71)
const C_BARREL_D := Color(0.36, 0.41, 0.465)
const C_TANK_T := Color(0.62, 0.72, 0.78)
const C_TANK_L := Color(0.475, 0.555, 0.615)
const C_TANK_R := Color(0.375, 0.445, 0.51)
const C_TANK_O := Color(0.28, 0.33, 0.38)
const C_SOIL := Color(0.478, 0.33, 0.198)
const C_SOIL_D := Color(0.36, 0.243, 0.14)
const C_SPROUT := Color(0.45, 0.745, 0.345)
const C_BUSH_D := Color(0.216, 0.435, 0.196)
const C_BUSH := Color(0.298, 0.555, 0.255)
const C_BUSH_H := Color(0.44, 0.7, 0.335)
const C_FLAGPOLE := Color(0.845, 0.865, 0.895)
const C_FLAG := Color(0.42, 0.72, 0.33)
const C_FLAG_D := Color(0.3, 0.55, 0.24)
const C_FLAG_EMBLEM := Color(0.95, 0.8, 0.32)
const C_SHADOW := Color(0, 0, 0, 0.24)

## 动画元素（_ready 内构建）
var _canvas: Node2D = null
var _flag_frames: Array[ImageTexture] = []
var _flag: Sprite2D = null
var _beacon: Sprite2D = null
var _flag_pos := Vector2i.ZERO
var _beacon_pos := Vector2i.ZERO
var _t := 0.0


func _ready() -> void:
	scale = Vector2(PIXEL_SCALE, PIXEL_SCALE)
	## 画布根：把画布坐标原点平移到节点中心（画布中心 = 本节点原点）
	_canvas = Node2D.new()
	_canvas.position = Vector2(-CANVAS_W, -CANVAS_H) / 2.0
	add_child(_canvas)
	_compose_static()
	_spawn_animated()


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_t += delta
	if _flag != null and not _flag_frames.is_empty():
		var frame_index := int(_t * 3.0) % _flag_frames.size()
		_flag.texture = _flag_frames[frame_index]
	if _beacon != null:
		_beacon.modulate.a = 0.4 + 0.6 * absf(sin(_t * 2.4))


## 格子 (gx,gy) 的菱形中心（虚拟画布坐标）。
func _tile_center(gx: int, gy: int) -> Vector2i:
	return Vector2i(ORIGIN_X + (gx - gy) * TILE_HW, ORIGIN_Y + (gx + gy) * TILE_HH + TILE_HH)


## 半格精度版本（跨格构图用）。
func _tile_center_f(gx: float, gy: float) -> Vector2i:
	return Vector2i(ORIGIN_X + int(round((gx - gy) * TILE_HW)),
			ORIGIN_Y + int(round((gx + gy) * TILE_HH)) + TILE_HH)


## ---- 静态场景合成 ----

func _compose_static() -> void:
	var img := PixelArtKit.canvas(CANVAS_W, CANVAS_H)
	_draw_platform(img)
	_draw_objects(img)
	var sprite := Sprite2D.new()
	sprite.texture = ImageTexture.create_from_image(img)
	sprite.centered = true
	sprite.position = Vector2(CANVAS_W, CANVAS_H) / 2.0
	_canvas.add_child(sprite)


func _draw_platform(img: Image) -> void:
	var cx := ORIGIN_X
	var top := Vector2i(cx, ORIGIN_Y)
	var left := Vector2i(cx - TILE_HW * PLATFORM_N, ORIGIN_Y + TILE_HH * PLATFORM_N)
	var right := Vector2i(cx + TILE_HW * PLATFORM_N, ORIGIN_Y + TILE_HH * PLATFORM_N)
	var bottom := Vector2i(cx, ORIGIN_Y + 2 * TILE_HH * PLATFORM_N)
	## 平台落影（整体略向下偏移的软菱形）
	PixelArtKit.soft_diamond(img, cx, bottom.y + 5,
			(bottom.x - left.x) + 4, (bottom.y - top.y) / 2 + 3, C_SHADOW)
	## 侧裙土层（左亮右暗）
	PixelArtKit.extrude_face(img, left.x, left.y, bottom.x, bottom.y, SKIRT_H, C_DIRT_L)
	PixelArtKit.extrude_face(img, bottom.x, bottom.y, right.x, right.y, SKIRT_H, C_DIRT_R)
	## 地砖（棋盘微差色 + 石板路）
	for gy in PLATFORM_N:
		for gx in PLATFORM_N:
			var p := _tile_center(gx, gy)
			PixelArtKit.diamond(img, p.x, p.y, TILE_HW, TILE_HH, _tile_color(gx, gy))
	## 平台边缘：前缘深色描边、后缘亮色草边
	PixelArtKit.line(img, left.x, left.y, bottom.x, bottom.y, C_EDGE_DARK)
	PixelArtKit.line(img, bottom.x, bottom.y, right.x, right.y, C_EDGE_DARK)
	PixelArtKit.line(img, left.x, left.y, top.x, top.y, C_EDGE_LIGHT)
	PixelArtKit.line(img, top.x, top.y, right.x, right.y, C_EDGE_LIGHT)


func _tile_color(gx: int, gy: int) -> Color:
	if PATH_TILES.has(Vector2i(gx, gy)):
		return C_PATH_A if (gx + gy) % 2 == 0 else C_PATH_B
	match (gx * 7 + gy * 13) % 4:
		0:
			return C_GRASS_A
		1:
			return C_GRASS_B
		2:
			return C_GRASS_C
		_:
			return C_GRASS_A


## 按等距深度（gx+gy）从后往前绘制。
func _draw_objects(img: Image) -> void:
	_draw_bush(img, _tile_center(2, 0) + Vector2i(-6, -2), 6)
	_draw_house(img)
	_draw_tank(img)
	_draw_plot(img)
	_draw_bush(img, _tile_center(1, 4) + Vector2i(-3, -1), 5)
	_draw_flagpole(img)
	_draw_canopy(img)
	_draw_bush(img, _tile_center(4, 2) + Vector2i(7, -3), 6)
	_draw_barrel(img, _tile_center(4, 3))


## 主屋：砂墙 + 砖红平顶 + 门/暖窗 + 天线（信标光点见动画层）。
func _draw_house(img: Image) -> void:
	var g := _tile_center(1, 1)
	var hw := 18
	var hh := 9
	var hz := 20
	var tc := Vector2i(g.x, g.y - hh - hz)
	var base_y := g.y
	PixelArtKit.soft_diamond(img, g.x + 3, base_y + 2, hw + 2, hh, C_SHADOW)
	PixelArtKit.extrude_face(img, tc.x - hw, tc.y, tc.x, tc.y + hh, hz, C_WALL_L)
	PixelArtKit.extrude_face(img, tc.x, tc.y + hh, tc.x + hw, tc.y, hz, C_WALL_R)
	## 门（左墙，底缘随墙体走势）
	for x in range(tc.x - 11, tc.x - 5):
		var gy := base_y - (tc.x - x) / 2
		PixelArtKit.vline(img, x, gy - 7, gy, C_DOOR)
	## 暖窗（右墙）
	for x in range(tc.x + 7, tc.x + 13):
		var gy := base_y - (x - tc.x) / 2
		PixelArtKit.vline(img, x, gy - 6, gy - 2, C_WINDOW_F)
	for x in range(tc.x + 8, tc.x + 12):
		var gy := base_y - (x - tc.x) / 2
		PixelArtKit.vline(img, x, gy - 5, gy - 3, C_WINDOW)
	## 屋檐 + 屋顶
	PixelArtKit.diamond(img, tc.x, tc.y + 1, hw + 1, hh + 1, C_ROOF_D)
	PixelArtKit.diamond(img, tc.x, tc.y, hw, hh, C_ROOF)
	## 天线（光点为动画贴图）
	PixelArtKit.vline(img, tc.x, tc.y - hh - 6, tc.y - hh, C_ANTENNA)
	_beacon_pos = Vector2i(tc.x, tc.y - hh - 6)


## 水塔：蓝灰金属立方体。
func _draw_tank(img: Image) -> void:
	var g := _tile_center(3, 0)
	var hw := 9
	var hh := 5
	var hz := 14
	PixelArtKit.soft_diamond(img, g.x + 2, g.y + 1, hw + 2, hh, C_SHADOW)
	var tc := Vector2i(g.x, g.y - hh - hz)
	PixelArtKit.cube(img, tc.x, tc.y, hw, hh, hz, C_TANK_T, C_TANK_L, C_TANK_R)
	PixelArtKit.cube_outline(img, tc.x, tc.y, hw, hh, hz, C_TANK_O)


## 菜园：土色菱形地块 + 三条垄沟 + 菜苗。
func _draw_plot(img: Image) -> void:
	var g := _tile_center_f(0.5, 2.5)
	PixelArtKit.diamond(img, g.x, g.y, 20, 10, C_SOIL)
	var rows := [[-15, -2, 5, 7], [-10, -5, 10, 5], [-5, -7, 14, 3]]
	for r in rows:
		var x0: int = r[0]
		var y0: int = r[1]
		var x1: int = r[2]
		var y1: int = r[3]
		PixelArtKit.line(img, g.x + x0, g.y + y0, g.x + x1, g.y + y1, C_SOIL_D)
		var mx := (x0 + x1) / 2
		var my := (y0 + y1) / 2
		PixelArtKit.px(img, g.x + mx, g.y + my - 2, C_SPROUT)
		PixelArtKit.px(img, g.x + mx + 1, g.y + my - 3, C_SPROUT)


## 旗杆（静态）；飘动的旗面为动画贴图。
func _draw_flagpole(img: Image) -> void:
	var g := _tile_center(4, 0)
	PixelArtKit.soft_diamond(img, g.x, g.y + 1, 6, 3, C_SHADOW)
	PixelArtKit.px(img, g.x, g.y - 29, C_FLAGPOLE)
	PixelArtKit.vline(img, g.x, g.y - 28, g.y, C_FLAGPOLE)
	_flag_pos = Vector2i(g.x + 1, g.y - 27)


## 仓库棚：四柱平顶（覆盖三格），棚下放木箱；整体抬升 lift 形成棚下空间。
func _draw_canopy(img: Image) -> void:
	var lift := 20
	var hw := 29
	var hh := 15
	var hz := 5
	for p in [_tile_center(2, 3), _tile_center(3, 3), _tile_center(3, 2)]:
		PixelArtKit.vline(img, p.x, p.y - lift, p.y, C_POLE)
	_draw_crate(img, _tile_center(2, 3) + Vector2i(-3, 2))
	var c := _tile_center_f(8.0 / 3.0, 8.0 / 3.0)
	var tc := Vector2i(c.x, c.y - lift)
	PixelArtKit.extrude_face(img, tc.x - hw, tc.y, tc.x, tc.y + hh, hz, C_CANOPY_L)
	PixelArtKit.extrude_face(img, tc.x, tc.y + hh, tc.x + hw, tc.y, hz, C_CANOPY_R)
	PixelArtKit.diamond(img, tc.x, tc.y, hw, hh, C_CANOPY)
	## 顶面拼板缝（沿等距轴，过中心对称）
	for s in [1.0 / 3.0, 2.0 / 3.0]:
		var ax := tc.x - int(round(hw * (1.0 - s)))
		var ay := tc.y - int(round(hh * s))
		PixelArtKit.line(img, ax, ay, tc.x * 2 - ax, tc.y * 2 - ay, C_CANOPY_SEAM)


func _draw_crate(img: Image, g: Vector2i) -> void:
	var hw := 7
	var hh := 4
	var hz := 9
	var tc := Vector2i(g.x, g.y - hh - hz)
	PixelArtKit.cube(img, tc.x, tc.y, hw, hh, hz, C_CRATE_T, C_CRATE_L, C_CRATE_R)
	PixelArtKit.cube_outline(img, tc.x, tc.y, hw, hh, hz, C_CRATE_O)
	## 板条横缝
	PixelArtKit.line(img, tc.x - hw, tc.y + 4, tc.x, tc.y + hh + 4, C_CRATE_O)
	PixelArtKit.line(img, tc.x, tc.y + hh + 4, tc.x + hw, tc.y + 4, C_CRATE_O)


func _draw_barrel(img: Image, g: Vector2i) -> void:
	var rx := 6
	var ry := 3
	var top_cy := g.y - 14
	var base_cy := g.y - 2
	PixelArtKit.soft_diamond(img, g.x, g.y + 1, rx + 2, 3, C_SHADOW)
	PixelArtKit.rect(img, g.x - rx, top_cy, rx * 2, base_cy - top_cy, C_BARREL)
	PixelArtKit.ellipse(img, g.x, base_cy, rx, ry, C_BARREL_D)
	PixelArtKit.ellipse(img, g.x, top_cy, rx, ry, C_BARREL_T)
	PixelArtKit.vline(img, g.x + rx - 1, top_cy + 1, base_cy - 1, C_BARREL_D)
	PixelArtKit.hline(img, g.x - rx + 1, g.x + rx - 1, top_cy + 5, C_BARREL_D)
	PixelArtKit.hline(img, g.x - rx + 1, g.x + rx - 1, base_cy - 4, C_BARREL_D)


func _draw_bush(img: Image, c: Vector2i, r: int) -> void:
	PixelArtKit.soft_diamond(img, c.x, c.y + 2, r + 1, (r + 1) / 2, C_SHADOW)
	PixelArtKit.ellipse(img, c.x, c.y, r, (2 * r) / 3 + 1, C_BUSH_D)
	PixelArtKit.ellipse(img, c.x, c.y - 1, maxi(r - 2, 1), maxi((2 * r) / 3 - 1, 1), C_BUSH)
	PixelArtKit.px(img, c.x - r / 2, c.y - r / 2, C_BUSH_H)
	PixelArtKit.px(img, c.x - r / 2 + 1, c.y - r / 2 - 1, C_BUSH_H)


## ---- 动画元素 ----

func _spawn_animated() -> void:
	_flag_frames = _make_flag_frames()
	_flag = Sprite2D.new()
	_flag.centered = false
	_flag.position = Vector2(_flag_pos)
	_flag.texture = _flag_frames[0]
	_canvas.add_child(_flag)
	_beacon = Sprite2D.new()
	var bimg := PixelArtKit.canvas(2, 2)
	bimg.fill_rect(Rect2i(0, 0, 2, 2), Color(1.0, 0.9, 0.5))
	_beacon.texture = ImageTexture.create_from_image(bimg)
	_beacon.position = Vector2(_beacon_pos)
	_canvas.add_child(_beacon)


## 旗面三帧：整列按波形表垂直错位，形成飘动。
func _make_flag_frames() -> Array[ImageTexture]:
	var waves := [
		[0, 0, 1, 1, 1, 0, 0, -1, -1, -1, 0, 0, 0],
		[0, 1, 1, 0, 0, -1, -1, -1, 0, 0, 1, 1, 0],
		[1, 1, 0, 0, -1, -1, 0, 0, 1, 1, 1, 0, 0],
	]
	var frames: Array[ImageTexture] = []
	for f in waves.size():
		var wave: Array = waves[f]
		var img := PixelArtKit.canvas(13, 8)
		for x in 13:
			var dy: int = wave[x]
			for yy in range(maxi(dy, 0), mini(7 + dy, 7) + 1):
				var c := C_FLAG if yy < 6 else C_FLAG_D
				if x >= 3 and x <= 5 and yy >= 2 and yy <= 4:
					c = C_FLAG_EMBLEM
				PixelArtKit.px(img, x, yy, c)
		frames.append(ImageTexture.create_from_image(img))
	return frames
