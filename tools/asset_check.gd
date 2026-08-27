## asset_check.gd —— 美术资产整备校验工具（视觉升级 V1 / M3）
##
## 用法（headless）：
##   godot --headless --path . -s res://tools/asset_check.gd
##
## 职责：
##   按 docs/art/art-pipeline.md 校验 assets/art 下的 plate/props 资产：
##   命名规范、尺寸（读 WarehouseView.DEFAULT_LAYOUT 单一来源，2x 规格）、
##   透明底与裁边、plate 不透明性、色板偏离度报告。存在不合格项时退出码 1
##   （可挂 CI）。资产缺失不算失败（占位图运行时兜底），只提示待补清单。
##
## 说明：直接读文件字节解码 PNG，不依赖编辑器导入状态，刚落盘即可校验。

extends SceneTree

## 色板 token（与 docs/art/art-pipeline.md / PixelUiKit 对齐）
const PALETTE := [
	Color("3b67c8"), Color("284a9a"), Color("5b85da"),
	Color("f8f1e1"), Color("efe0c4"),
	Color("f4c044"), Color("ce9655"), Color("8e6232"),
	Color("4ab08a"), Color("d9dde0"), Color("d1d4d9"),
]
## 最近色板距离超过该值（RGB 欧氏，0~1 尺度）计入偏离像素
const PALETTE_TOLERANCE := 0.28

var _failures: Array[String] = []
var _missing: Array[String] = []


func _initialize() -> void:
	print("==== FullHaul 美术资产整备校验 ====")
	_check_plate()
	_check_props()
	print("")
	if not _missing.is_empty():
		print("待补资产（运行时由程序化占位兜底）:")
		for m in _missing:
			print("  - ", m)
		print("")
	if _failures.is_empty():
		print("结论：PASS（不合格 0 项）")
		quit(0)
	else:
		print("结论：FAIL（不合格 %d 项）" % _failures.size())
		for f in _failures:
			print("  ✗ ", f)
		quit(1)


func _check_plate() -> void:
	var path := "res://assets/art/plates/warehouse_plate.png"
	var expect := Vector2i(WarehouseView.PLATE_SIZE) * 2
	var img := _load_png(path)
	if img == null:
		_missing.append("plates/warehouse_plate.png（%dx%d）" % [expect.x, expect.y])
		return
	_size_check(path, img, expect, true)
	_opaque_check(path, img)
	_palette_report(path, img)


func _check_props() -> void:
	var props: Array = WarehouseView.DEFAULT_LAYOUT.props
	for p in props:
		var id := String(p.id)
		var path := "res://assets/art/props/%s.png" % id
		var expect := Vector2i(float(p.size[0]), float(p.size[1])) * 2
		if not _name_ok(id + ".png"):
			_failures.append("%s：命名不符合 snake_case.png 规范" % path)
		var img := _load_png(path)
		if img == null:
			_missing.append("props/%s.png（%dx%d）" % [id, expect.x, expect.y])
			continue
		_size_check(path, img, expect, false)
		_alpha_check(path, img)
		_palette_report(path, img)


func _load_png(path: String) -> Image:
	if not FileAccess.file_exists(path):
		return null
	var bytes := FileAccess.get_file_as_bytes(path)
	var img := Image.new()
	if img.load_png_from_buffer(bytes) != OK:
		_failures.append("%s：PNG 解码失败" % path)
		return null
	return img


func _size_check(path: String, img: Image, expect: Vector2i, is_plate: bool) -> void:
	var got := Vector2i(img.get_width(), img.get_height())
	if got != expect:
		_failures.append("%s：尺寸 %s ≠ 规格%s %s（1x=%s）" % [path, got,
				"底图" if is_plate else "叠层物", expect, expect / 2])


func _opaque_check(path: String, img: Image) -> void:
	img.convert(Image.FORMAT_RGBA8)
	for y in img.get_height():
		for x in img.get_width():
			if img.get_pixel(x, y).a < 0.99:
				_failures.append("%s：底图应完全不透明（发现透明像素）" % path)
				return


func _alpha_check(path: String, img: Image) -> void:
	img.convert(Image.FORMAT_RGBA8)
	var w := img.get_width()
	var h := img.get_height()
	var transparent := 0
	var margin := 999999
	for y in h:
		for x in w:
			var a := img.get_pixel(x, y).a
			if a < 0.08:
				transparent += 1
			else:
				margin = mini(margin, mini(x, mini(y, mini(w - 1 - x, h - 1 - y))))
	var total := w * h
	if transparent == 0:
		_failures.append("%s：叠层物应为透明底（未发现透明像素，疑似未去底）" % path)
	elif float(transparent) / float(total) < 0.1:
		_failures.append("%s：透明占比不足 10%%（%d/%d），疑似去底不净" % [path, transparent, total])
	if margin < 4:
		_failures.append("%s：主体距画布边 %dpx < 4px（存在裁边风险）" % [path, margin])


func _name_ok(filename: String) -> bool:
	var regex := RegEx.new()
	regex.compile("^[a-z][a-z0-9_]*\\.png$")
	return regex.search(filename) != null


## 色板偏离度报告：抽样统计离最近 token 过远的像素占比并列主色。
func _palette_report(path: String, img: Image) -> void:
	img.convert(Image.FORMAT_RGBA8)
	var sampled := 0
	var off := 0
	var counts := {}
	for y in range(0, img.get_height(), 4):
		for x in range(0, img.get_width(), 4):
			var c := img.get_pixel(x, y)
			if c.a < 0.5:
				continue
			sampled += 1
			var best := 1.0
			var key := Color(c.r8 >> 4, c.g8 >> 4, c.b8 >> 4)
			var int_key := Vector3i(int(c.r8) >> 4, int(c.g8) >> 4, int(c.b8) >> 4)
			counts[int_key] = int(counts.get(int_key, 0)) + 1
			for token in PALETTE:
				var d := Vector3(c.r - token.r, c.g - token.g, c.b - token.b).length()
				best = minf(best, d)
			if best > PALETTE_TOLERANCE:
				off += 1
	if sampled == 0:
		return
	var ratio := float(off) / float(sampled)
	var flag := "OK" if ratio < 0.25 else "偏离偏高（建议重 roll 或扩充色板 token）"
	print("%s：抽样 %d，色板外像素 %.1f%% —— %s" % [path, sampled, ratio * 100.0, flag])
