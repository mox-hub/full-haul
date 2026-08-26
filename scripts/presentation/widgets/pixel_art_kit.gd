## pixel_art_kit.gd —— FullHaul 表现层：程序化像素画具（等距 2.5D 原语）
##
## 职责：
##   提供在低分辨率 Image 上绘制等距像素画的基础原语：菱形（地砖/顶面）、
##   竖直挤出面（立方体侧壁）、线段、椭圆、软落影等。低分辨率画布经视图层
##   整数倍最近邻（TEXTURE_FILTER_NEAREST）放大后呈现像素化 2.5D 视觉
##   （首页基地，WORD-40）。
##
## 设计要点：
##   - 纯静态工具类：零节点依赖，输入/输出均为 Image 与基础类型。
##   - 所有写入自动做画布边界裁剪，调用方无需关心越界。
##   - 颜色/构图等场景语义由使用方（BaseView）定义，本类不含业务含义。

extends RefCounted
class_name PixelArtKit


## 新建一张透明低分辨率画布（RGBA8）。
static func canvas(w: int, h: int) -> Image:
	return Image.create_empty(maxi(w, 1), maxi(h, 1), false, Image.FORMAT_RGBA8)


## 单点写入（越界裁剪，直接覆盖）。
static func px(img: Image, x: int, y: int, c: Color) -> void:
	if _inside(img, x, y):
		img.set_pixel(x, y, c)


## 单点 alpha 混合写入（用于半透明落影等覆盖层）。
static func blend_px(img: Image, x: int, y: int, c: Color) -> void:
	if not _inside(img, x, y):
		return
	var d := img.get_pixel(x, y)
	var out_a := c.a + d.a * (1.0 - c.a)
	if out_a <= 0.0:
		return
	var r := (c.r * c.a + d.r * d.a * (1.0 - c.a)) / out_a
	var g := (c.g * c.a + d.g * d.a * (1.0 - c.a)) / out_a
	var b := (c.b * c.a + d.b * d.a * (1.0 - c.a)) / out_a
	img.set_pixel(x, y, Color(r, g, b, out_a))


static func hline(img: Image, x0: int, x1: int, y: int, c: Color) -> void:
	for x in range(mini(x0, x1), maxi(x0, x1) + 1):
		px(img, x, y, c)


static func vline(img: Image, x: int, y0: int, y1: int, c: Color) -> void:
	for y in range(mini(y0, y1), maxi(y0, y1) + 1):
		px(img, x, y, c)


## Bresenham 线段（描边/垄沟用）。
static func line(img: Image, x0: int, y0: int, x1: int, y1: int, c: Color) -> void:
	var dx := absi(x1 - x0)
	var dy := -absi(y1 - y0)
	var sx := 1 if x1 >= x0 else -1
	var sy := 1 if y1 >= y0 else -1
	var err := dx + dy
	var x := x0
	var y := y0
	while true:
		px(img, x, y, c)
		if x == x1 and y == y1:
			return
		var e2 := 2 * err
		if e2 >= dy:
			err += dy
			x += sx
		if e2 <= dx:
			err += dx
			y += sy


## 实心矩形。
static func rect(img: Image, x: int, y: int, w: int, h: int, c: Color) -> void:
	for dy in h:
		hline(img, x, x + w - 1, y + dy, c)


## 实心菱形：中心 (cx,cy)，半宽 hw，半高 hh（等距 2:1 地砖取 hw = 2*hh）。
static func diamond(img: Image, cx: int, cy: int, hw: int, hh: int, c: Color) -> void:
	hw = maxi(hw, 0)
	hh = maxi(hh, 1)
	for dy in range(-hh, hh + 1):
		var half := int(round(float(hw) * (1.0 - float(absi(dy)) / float(hh))))
		hline(img, cx - half, cx + half, cy + dy, c)


## 菱形的 alpha 混合版本（物体落影）。
static func soft_diamond(img: Image, cx: int, cy: int, hw: int, hh: int, c: Color) -> void:
	hw = maxi(hw, 0)
	hh = maxi(hh, 1)
	for dy in range(-hh, hh + 1):
		var half := int(round(float(hw) * (1.0 - float(absi(dy)) / float(hh))))
		for x in range(cx - half, cx + half + 1):
			blend_px(img, x, cy + dy, c)


## 实心椭圆。
static func ellipse(img: Image, cx: int, cy: int, rx: int, ry: int, c: Color) -> void:
	rx = maxi(rx, 0)
	ry = maxi(ry, 1)
	for dy in range(-ry, ry + 1):
		var t := 1.0 - float(dy * dy) / float(ry * ry)
		var half := int(round(float(rx) * sqrt(maxf(t, 0.0))))
		hline(img, cx - half, cx + half, cy + dy, c)


## 竖直挤出面：顶边从 (ax,ay) 到 (bx,by)，向下挤出 h 像素。
## 按列竖直填充，恰好铺满平行四边形（等距立方体的左/右侧壁）。
static func extrude_face(img: Image, ax: int, ay: int, bx: int, by: int, h: int, c: Color) -> void:
	var dx := bx - ax
	if dx == 0:
		vline(img, ax, mini(ay, by), maxi(ay, by) + h, c)
		return
	var step := 1 if dx > 0 else -1
	for x in range(ax, bx + step, step):
		var t := float(x - ax) / float(dx)
		var y := ay + int(round(float(by - ay) * t))
		vline(img, x, y, y + h, c)


## 等距立方体：顶面中心 (cx,cy)、半宽 hw、半高 hh、柱高 hz；
## 顶/左/右三面分色以营造固定受光方向。
static func cube(img: Image, cx: int, cy: int, hw: int, hh: int, hz: int,
		top_c: Color, left_c: Color, right_c: Color) -> void:
	extrude_face(img, cx - hw, cy, cx, cy + hh, hz, left_c)
	extrude_face(img, cx, cy + hh, cx + hw, cy, hz, right_c)
	diamond(img, cx, cy, hw, hh, top_c)


## 立方体选择性描边：顶面前缘 + 两侧竖棱 + 底缘（像素画的轮廓感）。
static func cube_outline(img: Image, cx: int, cy: int, hw: int, hh: int, hz: int, c: Color) -> void:
	line(img, cx - hw, cy, cx, cy + hh, c)
	line(img, cx, cy + hh, cx + hw, cy, c)
	vline(img, cx - hw, cy, cy + hz, c)
	vline(img, cx + hw, cy, cy + hz, c)
	line(img, cx - hw, cy + hz, cx, cy + hh + hz, c)
	line(img, cx, cy + hh + hz, cx + hw, cy + hz, c)


static func _inside(img: Image, x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height()
