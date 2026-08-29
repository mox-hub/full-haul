## warehouse_view.gd —— FullHaul 表现层：首页仓库场景视图（3D 体块重建 V2）
##
## 职责：
##   以真实 3D 网格呈现等距俯视仓库内景：ground 地砖阵列铺地、wall 段砌
##   两侧后墙、box/cylinder/sphere 组合道具（货架/木箱/油桶/托盘车/盆栽/
##   卷帘门），纯色 StandardMaterial3D 保持扁平卡通观感。Camera3D 挂 Rig
##   负责进场推拉（dolly）、拖动平移与滚轮缩放（dolly × zoom 复合作用于
##   相机距离）；可交互物件挂 StaticBody3D 热点，
##   点击经物理射线命中后以 prop_activated 信号交回页面层。
##   纯表现组件，不接事件总线。
##
## 模型约定（assets/models/warehouse/，gitignore 本地资产）：
##   文件名即尺寸（cm，100=1m），原点在足迹中心、底面 y=0；缺文件时
##   对应件静默跳过（本地资产不入库，见 .gitignore）。
##
## 坐标约定：世界 1 单位 = 1m = 100 design px；DEFAULT_LAYOUT 的 pos/size
## 仍为 design px（pos = 等距地坪上的足迹中心，以房间中心为原点映射世界），
## apply_layout()/current_layout() 字典形态与 V1 保持一致（建造模式预留）。

extends Node3D
class_name WarehouseView

## 点击命中叠层物（action 由页面层解释：warehouse=开仓库弹窗 extract=撤离伏笔）
signal prop_activated(prop_id: String, action: String)

## 房间设计尺寸与中心（design px；世界映射 = (pos - center) * PX2M）
const PLATE_SIZE := Vector2(1080, 760)
const ROOM_CENTER := Vector2(540.0, 512.0)
const PX2M := 0.01
## 进场推拉参数（dolly：起始拉近 6% 后缓出回位）
const ZOOM_IN_STEP := 0.94
const PUSH_DURATION := 0.4
## 滚轮缩放：单格倍率与限幅（除在相机距离上，>1 拉近 <1 拉远）
const WHEEL_ZOOM_STEP := 1.1
const ZOOM_MIN := 0.55
const ZOOM_MAX := 1.7
## 体块模型目录（文件名即尺寸，cm；本地资产不入库）
const MODEL_DIR := "res://assets/models/warehouse/"
## 等距相机：偏航 45°、俯角约 31°（CAM_DIR.y 决定）
const CAM_DIR := Vector3(1.0, 0.85, 1.0)
const CAM_DIST := 16.5
const CAM_FOV := 40.0
const AIM_Y := 0.7

## 默认布局（design px）：pos = 足迹中心、size = 热点矩形；数组顺序即旧版
## 前后遮挡序（3D 下由深度代替，仅保留数据兼容）；货架→仓库弹窗、
## 卷帘门→撤离伏笔。roll_door 的 pos.x 解释为沿右后墙的横向位置。
const DEFAULT_LAYOUT := {
	"plate": "res://assets/models/warehouse",
	"props": [
		{"id": "roll_door", "pos": [880, 374], "size": [100, 190], "layer": "mid", "hotspot": true, "action": "extract", "hint": "卷帘门"},
		{"id": "plants", "pos": [310, 390], "size": [85, 95], "layer": "mid", "hotspot": false, "action": "", "hint": "盆栽"},
		{"id": "shelf_b", "pos": [660, 430], "size": [150, 180], "layer": "mid", "hotspot": true, "action": "warehouse", "hint": "货架 B"},
		{"id": "shelf_a", "pos": [330, 520], "size": [150, 180], "layer": "mid", "hotspot": true, "action": "warehouse", "hint": "货架 A"},
		{"id": "barrels", "pos": [870, 510], "size": [95, 110], "layer": "mid", "hotspot": false, "action": "", "hint": "油桶"},
		{"id": "crate_stack", "pos": [560, 620], "size": [170, 120], "layer": "mid", "hotspot": true, "action": "warehouse", "hint": "地堆木箱"},
		{"id": "pallet_jack", "pos": [430, 660], "size": [140, 90], "layer": "fore", "hotspot": false, "action": "", "hint": "托盘车"},
	],
}

# ---- 配色（对齐 PixelUiKit 概念图调色板；纯色粗糙材质 = 扁平卡通）----
const C_FLOOR := Color(0.851, 0.867, 0.878)
const C_FLOOR_ALT := Color(0.812, 0.83, 0.843)
const C_WALL := Color(0.231, 0.404, 0.784)
const C_WALL_R := Color(0.208, 0.364, 0.706)
const C_WOOD := Color(0.808, 0.588, 0.333)
const C_WOOD_DK := Color(0.68, 0.49, 0.27)
const C_WOOD_LT := Color(0.86, 0.65, 0.4)
const C_TEAL := Color(0.29, 0.69, 0.54)
const C_STEEL := Color(0.62, 0.66, 0.71)
const C_STEEL_HI := Color(0.82, 0.83, 0.85)
const C_STEEL_DK := Color(0.45, 0.47, 0.52)
const C_FLOOR_LINE := Color(0.957, 0.753, 0.267)
const C_MARK_RED := Color(0.82, 0.333, 0.302)

var camera: Camera3D = null
## 相机平移偏移（design px；由页面层拖动驱动，受 pan_bounds 约束）
var _pan := Vector2.ZERO
var _rig: Node3D = null
var _content: Node3D = null
var _door_lamp: MeshInstance3D = null
var _door_lamp_base := Vector3.ONE
var _hotspots: Array[Dictionary] = []
var _mats: Dictionary = {}
var _pushed_in := false
var _t := 0.0
## dolly（进场推拉）与 zoom（滚轮）分立，实际相机距离 = CAM_DIST × 两者之积
var _dolly := 1.0
var _zoom := 1.0


func _ready() -> void:
	_build_camera()
	_build_environment()
	_apply_layout(DEFAULT_LAYOUT)
	## 视口尺寸由 SubViewportContainer(stretch) 就绪后才有意义，延迟一帧推拉
	call_deferred("play_push_in")


func _process(delta: float) -> void:
	_t += delta
	## 卷帘门警示灯呼吸（缩放脉冲，对应旧版 modulate 呼吸）
	if _door_lamp != null:
		var s := 1.0 + 0.18 * sin(_t * 2.2)
		_door_lamp.scale = _door_lamp_base * s


## ---- 对外接口 ----

## 相机允许的平移范围（±，design px）：房间超出视口的部分。
func pan_bounds() -> Vector2:
	var vp := get_viewport().get_visible_rect().size
	return Vector2(maxf(PLATE_SIZE.x - vp.x, 0.0), maxf(PLATE_SIZE.y - vp.y, 0.0)) / 2.0


## 当前平移偏移（页面层在拖动起点的快照与点击判定用）。
func pan() -> Vector2:
	return _pan


## 页面层拖动入口：偏移量自动 clamp 到房间边界内（同 V1 的屏幕平移语义）。
func set_pan(offset: Vector2) -> void:
	_pan = offset.clamp(-pan_bounds(), pan_bounds())
	if _rig != null:
		_rig.position = Vector3(_pan.x, 0.0, _pan.y) * PX2M


## 当前缩放倍率（1.0 为默认取景；测试/预览工具与页面层留痕用）。
func zoom() -> float:
	return _zoom


## 滚轮缩放入口：factor 除到当前倍率上并 clamp 限幅（如 set_zoom(1.1) 拉近）。
func set_zoom(factor: float) -> void:
	_zoom = clampf(_zoom / factor, ZOOM_MIN, ZOOM_MAX)
	_apply_camera()


## 命中测试：视口坐标发射线，只与热点 StaticBody3D 相交。
func try_activate_at(canvas_pos: Vector2) -> bool:
	if camera == null:
		return false
	var from := camera.project_ray_origin(canvas_pos)
	var to := from + camera.project_ray_normal(canvas_pos) * 100.0
	var query := PhysicsRayQueryParameters3D.create(from, to)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.has("collider"):
		return false
	var body: Object = hit["collider"]
	if body is StaticBody3D and (body as StaticBody3D).has_meta("prop_id"):
		var id := str((body as StaticBody3D).get_meta("prop_id"))
		for h in _hotspots:
			if h.id == id:
				if h.hotspot:
					prop_activated.emit(id, h.action)
				return true
	return false


## 某物件中心投影到视口的坐标（测试/预览工具用）。
func prop_center(prop_id: String) -> Vector2:
	for h in _hotspots:
		if h.id == prop_id:
			return camera.unproject_position(h.center)
	return Vector2(get_viewport().get_visible_rect().size) / 2.0


## 建造模式预留：替换布局并重建场景。
func apply_layout(layout: Dictionary) -> void:
	_apply_layout(layout)


## 建造模式预留：当前布局快照（可序列化存档）。
func current_layout() -> Dictionary:
	return {"plate": DEFAULT_LAYOUT.plate,
		"props": DEFAULT_LAYOUT.props.duplicate(true)}


## ---- 场景构建 ----

func _build_environment() -> void:
	var env := Environment.new()
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1, 1, 1)
	env.ambient_light_energy = 0.85
	camera.environment = env
	## 左上受光（art-pipeline 规范）：屏幕左上 ≈ 世界 -right + up 方向
	var light := DirectionalLight3D.new()
	light.light_energy = 0.9
	add_child(light)
	light.look_at_from_position(Vector3(-0.6, 1.0, 0.8) * 10.0, Vector3.ZERO)


func _build_camera() -> void:
	_rig = Node3D.new()
	add_child(_rig)
	camera = Camera3D.new()
	camera.fov = CAM_FOV
	_apply_camera()
	_rig.add_child(camera)
	camera.look_at(Vector3(0, AIM_Y, 0))
	camera.make_current()


## 按当前 dolly × zoom 摆放相机（缩放围绕注视点 AIM_Y，视线方向不变）。
func _apply_camera() -> void:
	if camera != null:
		camera.position = Vector3(0, AIM_Y, 0) + CAM_DIR.normalized() * (CAM_DIST * _dolly * _zoom)


func _apply_layout(layout: Dictionary) -> void:
	if _content != null:
		_content.queue_free()
	_hotspots.clear()
	_door_lamp = null
	_content = Node3D.new()
	add_child(_content)
	_build_ground()
	_build_walls()
	for prop_def in layout.get("props", []):
		var p: Dictionary = prop_def.duplicate()
		p.pos = Vector2(p.pos[0], p.pos[1])
		p.size = Vector2(p.size[0], p.size[1])
		var world := _world_pos(p.pos)
		var center := world
		match String(p.id):
			"roll_door":
				center = _build_roll_door(p.pos.x)
			"plants":
				_build_plants(world)
			"shelf_a", "shelf_b":
				_build_shelf(world)
			"barrels":
				_build_barrels(world)
			"crate_stack":
				_build_crates(world)
			"pallet_jack":
				_build_pallet_jack(world)
		if bool(p.get("hotspot", false)):
			_add_hotspot(String(p.id), center, p.size, bool(p.hotspot), String(p.get("action", "")))


## design px（plate 本地系）→ 世界坐标（房间中心为原点，y=0 地面）
func _world_pos(pos: Vector2) -> Vector3:
	return Vector3((pos.x - ROOM_CENTER.x) * PX2M, 0.0, (pos.y - ROOM_CENTER.y) * PX2M)


## 纯色粗糙材质（按色缓存；扁平卡通 = 无金属、无发光）
func _flat_mat(color: Color) -> StandardMaterial3D:
	if not _mats.has(color):
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		mat.roughness = 1.0
		_mats[color] = mat
	return _mats[color]


## 放置一个网格实例；scale_v 以模型自然米径为 1（模型原始单位 cm，内部
## 统一 ×PX2M 换算）。模型缺失返回 null（本地资产不入库，静默跳过）。
func _place(mesh_name: String, pos: Vector3, yaw_deg: float, scale_v: Vector3,
		color: Color, parent: Node3D = null) -> MeshInstance3D:
	var mesh: Mesh = load(MODEL_DIR + mesh_name)
	if mesh == null:
		return null
	var inst := MeshInstance3D.new()
	inst.mesh = mesh
	inst.material_override = _flat_mat(color)
	inst.position = pos
	inst.rotation.y = deg_to_rad(yaw_deg)
	inst.scale = scale_v * PX2M
	(parent if parent != null else _content).add_child(inst)
	return inst


## 地砖阵列：11×8 张 1m 地砖，顶面齐 y=0，微棋盘色差当砖缝。
func _build_ground() -> void:
	for i in 11:
		for j in 8:
			var x := -5.5 + 0.5 + i
			var z := -4.0 + 0.5 + j
			var c := C_FLOOR if (i + j) % 2 == 0 else C_FLOOR_ALT
			_place("ground-1-1-01.obj", Vector3(x, -0.1, z), 0.0, Vector3.ONE, c)


## 两侧后墙（-Z 右后 / -X 左后），墙段长边转 X 向砌右后墙。
func _build_walls() -> void:
	for i in 11:
		_place("wall-1-01-2.obj", Vector3(-5.0 + i, 0.0, -3.85), 90.0, Vector3.ONE, C_WALL)
	for j in 8:
		_place("wall-1-01-2.obj", Vector3(-5.45, 0.0, -3.5 + j), 0.0, Vector3.ONE, C_WALL_R)


## 货架：高木箱体 + 顶面两件货箱（青绿/钢灰）。
func _build_shelf(at: Vector3) -> void:
	_place("box-05-05-1.obj", at, 0.0, Vector3(2.0, 1.6, 2.0), C_WOOD)
	_place("box-05-05-05.obj", at + Vector3(-0.22, 1.6, -0.1), 0.0, Vector3.ONE, C_TEAL)
	_place("box-05-05-05.obj", at + Vector3(0.2, 1.6, 0.14), 0.0, Vector3.ONE, C_STEEL)


## 地堆木箱：1m 大箱 + 侧旁与顶上两只 0.5m 小箱。
func _build_crates(at: Vector3) -> void:
	_place("box-1-1-1.obj", at, 0.0, Vector3.ONE, C_WOOD)
	_place("box-05-05-05.obj", at + Vector3(-0.72, 0.0, 0.34), 20.0, Vector3.ONE, C_WOOD_DK)
	_place("box-05-05-05.obj", at + Vector3(0.16, 1.0, -0.08), -14.0, Vector3.ONE, C_WOOD_LT)


## 油桶：两只 0.9m 高钢桶。
func _build_barrels(at: Vector3) -> void:
	_place("Cylinder025-1.obj", at + Vector3(-0.26, 0.0, 0.1), 0.0, Vector3(0.9, 0.9, 0.9), C_STEEL)
	_place("Cylinder025-1.obj", at + Vector3(0.24, 0.0, -0.14), 0.0, Vector3(0.9, 0.9, 0.9), C_STEEL_DK)


## 盆栽：木色矮盆 + 青绿圆冠。
func _build_plants(at: Vector3) -> void:
	_place("box-05-05-05.obj", at, 0.0, Vector3(0.8, 0.7, 0.8), C_WOOD_DK)
	_place("Sphere-025.obj", at + Vector3(0.0, 0.5, 0.0), 0.0, Vector3(1.4, 1.4, 1.4), C_TEAL)


## 托盘车：低平黄色车板 + 后侧把手（前景件）。
func _build_pallet_jack(at: Vector3) -> void:
	_place("box-05-05-05.obj", at, 0.0, Vector3(2.4, 0.24, 1.6), C_FLOOR_LINE)
	_place("box-05-05-1.obj", at + Vector3(-0.5, 0.0, -0.3), 0.0, Vector3(0.16, 0.6, 0.16), C_STEEL_DK)


## 卷帘门：贴合右后墙内面的斜贴门板 + 顶部警示灯；返回热点中心（世界系）。
func _build_roll_door(along_x: float) -> Vector3:
	var x := (along_x - ROOM_CENTER.x) * PX2M
	var face_z := -3.8 + 0.06
	_place("box-05-05-1.obj", Vector3(x, 0.15, face_z), 0.0,
			Vector3(2.0, 1.35, 0.24), C_STEEL_HI)
	_door_lamp = _place("Sphere-025.obj", Vector3(x - 0.34, 1.6, face_z), 0.0,
			Vector3(0.24, 0.24, 0.24), C_MARK_RED)
	_door_lamp_base = Vector3(0.24, 0.24, 0.24) * PX2M
	return Vector3(x, 0.9, face_z)


## 热点：只含碰撞盒的 StaticBody3D（射线唯一可命中物），meta 记 prop_id。
func _add_hotspot(id: String, center: Vector3, size: Vector2, hotspot: bool,
		action: String) -> void:
	_hotspots.append({"id": id, "center": center, "hotspot": hotspot, "action": action})
	var body := StaticBody3D.new()
	body.set_meta("prop_id", id)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(maxf(size.x * PX2M, 0.4), 1.8, maxf(size.y * PX2M, 0.4))
	shape.shape = box
	body.add_child(shape)
	body.position = center + Vector3(0.0, 0.9, 0.0)
	_content.add_child(body)


## 进场推拉（dolly 预留为建造模式的手动缩放通道）。
func play_push_in() -> void:
	if _pushed_in or camera == null:
		return
	_pushed_in = true
	_dolly = ZOOM_IN_STEP
	_apply_camera()
	var tw := create_tween()
	tw.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_method(_set_dolly, ZOOM_IN_STEP, 1.0, PUSH_DURATION)


func _set_dolly(dolly: float) -> void:
	_dolly = dolly
	_apply_camera()
