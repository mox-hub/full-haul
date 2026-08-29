## model_preview_view.gd —— FullHaul 表现层：物品 3D 模型预览视口（视觉升级 V1）
##
## 职责：
##   在 2D UI 内嵌一个小型 3D 视口展示物品模型（项目首个 3D 用例）：
##   - 独立 World3D + 透明背景，可直接叠进仓库行 / 背包格
##   - 按网格 AABB 自动取景（斜 3/4 视角，长轴自动放平），可选慢速自转
##   - 定义→模型路径映射暂收编于此（表现层映射；3D 管线验证后再考虑
##     提升为 ItemDefinition 正式字段）
##   - 无映射（或加载失败）的定义回退品质色 1m 正方体占位；真模型落盘
##     后在 ITEM_MODEL_PATHS 登记即自动替换
##
## 用法：
##   var view := ModelPreviewView.create("item_scifi_pistol", 56.0)
##   view.clicked.connect(_on_preview_clicked)
##   背包格等锚定布局场景：create 后把 custom_minimum_size 清零再用锚点拉伸。

extends SubViewportContainer
class_name ModelPreviewView

## 物品定义 → 模型资源路径（新增 3D 物品在此登记）
const ITEM_MODEL_PATHS := {
	"item_scifi_pistol": "res://assets/models/han_gun/han_gun.obj",
}

## 占位正方体边长（米）：无专属模型的物品统一用它兜底
const PLACEHOLDER_CUBE_SIZE := 0.5

## 自转角速度（弧度/秒）
const SPIN_SPEED := 0.8
## 相机垂直视场角（度）；长物件用窄视场减少透视畸变
const CAMERA_FOV_DEG := 45.0
## 取景裕度系数（按包围盒对角线取距；侧视角下长物件投影更满）
const FRAME_MARGIN := 1.0
## 取景方位（斜 3/4 侧视，偏正面让长轴投影尽量占满视口）
const CAMERA_DIR := Vector3(0.4, 0.3, 1.0)

## 左键点击视口（供行/格转发打开大图弹窗）
signal clicked

## OBJ 网格静态缓存（同一模型多处预览共享一次 load）
static var _mesh_cache: Dictionary = {}

var _pivot: Node3D = null
var _spin := true


## 查询定义是否有 3D 模型；无映射返回空串。
static func model_path_for(definition_id: String) -> String:
	return ITEM_MODEL_PATHS.get(definition_id, "")


## 创建一份模型预览：view_size 为视口边长（design px），spin 控制自转，
## tint 为占位正方体的着色（调用方传品质色保持品质可辨识）。
static func create(definition_id: String, view_size: float, spin := true,
		tint: Color = Color(0.82, 0.82, 0.82)) -> ModelPreviewView:
	var view := ModelPreviewView.new()
	view.custom_minimum_size = Vector2(view_size, view_size)
	view.stretch = true
	view._spin = spin

	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	view.add_child(viewport)

	var mesh: Mesh = view._load_mesh(model_path_for(definition_id))
	var tinted := false
	if mesh == null:
		## 无专属模型（或加载失败）→ 品质色正方体占位，取景按其 AABB 照常工作
		var cube := BoxMesh.new()
		cube.size = Vector3.ONE * PLACEHOLDER_CUBE_SIZE
		mesh = cube
		tinted = true
	var aabb := mesh.get_aabb()

	var pivot := Node3D.new()
	viewport.add_child(pivot)
	view._pivot = pivot
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = mesh
	if tinted:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = tint
		mesh_instance.material_override = mat
	## 模型几何中心挪到轴心原点；长轴在 Y 时放平到 Z，保证自转姿态合理
	mesh_instance.position = -aabb.get_center()
	if aabb.size.y >= maxf(aabb.size.x, aabb.size.z):
		mesh_instance.rotation.x = -PI / 2.0
	pivot.add_child(mesh_instance)

	var camera := Camera3D.new()
	camera.fov = CAMERA_FOV_DEG
	camera.environment = _build_environment()
	viewport.add_child(camera)
	var radius: float = maxf(aabb.size.length() * 0.5, 0.001)
	var dist: float = radius / tan(deg_to_rad(CAMERA_FOV_DEG * 0.5)) * FRAME_MARGIN
	var cam_pos := CAMERA_DIR.normalized() * dist
	## create() 构建期节点尚未入树，不能走 look_at，手动构造朝原点的变换
	camera.transform = _aim_transform(cam_pos)

	viewport.add_child(_build_lights())
	return view


## 构造「位于 from、朝向原点」的节点变换（-Z 轴指向原点；构建期可安全使用）。
static func _aim_transform(from: Vector3) -> Transform3D:
	return Transform3D(Basis.looking_at(-from.normalized()), from)


## 透明背景 + 环境光（挂相机，避免再建 WorldEnvironment 节点）。
static func _build_environment() -> Environment:
	var env := Environment.new()
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1, 1, 1)
	env.ambient_light_energy = 0.75
	return env


## 主光 + 反向弱补光，模型双面都有基本明暗。
static func _build_lights() -> Node3D:
	var lights := Node3D.new()
	var key := DirectionalLight3D.new()
	key.transform = _aim_transform(Vector3(1.0, 1.6, 1.2))
	key.light_energy = 1.0
	lights.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.transform = _aim_transform(Vector3(-1.2, 0.4, -0.9))
	fill.light_energy = 0.35
	lights.add_child(fill)
	return lights


## 带缓存的网格加载；路径为空或加载失败返回 null（create 落正方体占位）。
static func _load_mesh(path: String) -> Mesh:
	if path.is_empty():
		return null
	if not _mesh_cache.has(path):
		_mesh_cache[path] = load(path)
	return _mesh_cache.get(path)


func _process(delta: float) -> void:
	if _spin and _pivot != null and is_visible_in_tree():
		_pivot.rotate_y(delta * SPIN_SPEED)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT \
			and event.pressed:
		clicked.emit()
