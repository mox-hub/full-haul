## generate_container_data.gd —— 容器 Resource 生成工具（一次性，可重复执行）
##
## 职责：
##   生成种子容器定义 data/containers/definitions/*.tres（ContainerData
##   资源，9 条：木箱/铁箱/撤离点 + 六种扩档容器），并新建/更新
##   data/containers/container_registry.tres（Yard Registry，string_id ->
##   UID + tier 属性索引）。
##
## 概率绑定：显式给出 rarity_weights/category_weights 的容器按绑定落盘；
## 未给出的（木箱/铁箱/撤离点）留空表——运行期回退共享 tier 权重表
## （container_tier_config）。重复生成沿用既有 UID，不漂移。
##
## 用法（本机 Godot 4.7.2 console 版）：
##   Godot_v4.7.2-stable_win64_console.exe --headless \
##     --path E:/Project/full-haul -s res://tools/generate_container_data.gd

extends SceneTree

const ContainerDataScript := preload("res://data/containers/container_data.gd")
const RegistryScript := preload("res://addons/yard/registry.gd")

const DEFINITIONS_DIR := "res://data/containers/definitions"
const REGISTRY_PATH := "res://data/containers/container_registry.tres"

## 共享 tier 品质权重（对齐 container_tier_config，供扩档容器引用拷贝）
const TIER_RARITY := {
	"C1": {"common": 60, "uncommon": 25, "rare": 10, "epic": 4, "legendary": 1},
	"C2": {"common": 45, "uncommon": 30, "rare": 18, "epic": 6, "legendary": 1},
	"C4": {"common": 5, "uncommon": 20, "rare": 40, "epic": 25, "legendary": 10},
	"C5": {"common": 2, "uncommon": 8, "rare": 30, "epic": 40, "legendary": 20},
}

## 种子容器（对齐内存后端既有种子 + 六种扩档；rarity/category 为概率绑定）
const SEED_CONTAINERS := [
	{
		"container_id": "crate_wood", "display_name": "木箱",
		"kind": 0, "tier": "C1", "grid": Vector2i(3, 3),
	},
	{
		"container_id": "crate_metal", "display_name": "铁箱",
		"kind": 0, "tier": "C3", "grid": Vector2i(4, 4),
	},
	{
		"container_id": "extract_heli", "display_name": "撤离点",
		"kind": 1, "tier": "C1", "grid": Vector2i(2, 2),
	},
	{
		"container_id": "carton_paper", "display_name": "文件纸箱",
		"kind": 0, "tier": "C1", "grid": Vector2i(2, 3),
		"category": {"intel": 12.0, "collectible": 2.0},
	},
	{
		"container_id": "supply_food", "display_name": "食品补给箱",
		"kind": 0, "tier": "C1", "grid": Vector2i(3, 2),
		"category": {"food": 12.0, "medical": 2.0},
	},
	{
		"container_id": "tool_locker", "display_name": "工具壁柜",
		"kind": 0, "tier": "C2", "grid": Vector2i(4, 2),
		"rarity": "C2",
		"category": {"tool": 8.0, "material": 6.0, "electronics": 2.0},
	},
	{
		"container_id": "cooler_medical", "display_name": "医疗冷藏箱",
		"kind": 0, "tier": "C2", "grid": Vector2i(3, 3),
		"rarity": "C2",
		"category": {"medical": 10.0, "food": 3.0},
	},
	{
		"container_id": "ammo_crate", "display_name": "军用弹药箱",
		"kind": 0, "tier": "C4", "grid": Vector2i(3, 3),
		"rarity": "C4",
		"category": {"electronics": 4.0, "tool": 4.0, "material": 2.0},
	},
	{
		"container_id": "wall_safe", "display_name": "嵌墙保险柜",
		"kind": 0, "tier": "C5", "grid": Vector2i(2, 2),
		"rarity": "C5",
		"category": {"collectible": 6.0, "electronics": 4.0, "intel": 2.0},
	},
]


func _initialize() -> void:
	var errors: Array = []
	var uid_by_string_id: Dictionary = {}
	var tier_index: Dictionary = {}

	for seed_def: Dictionary in SEED_CONTAINERS:
		var container_id := str(seed_def["container_id"])
		var path := "%s/%s.tres" % [DEFINITIONS_DIR, container_id]

		var container = ContainerDataScript.new()
		container.container_id = container_id
		container.display_name = str(seed_def["display_name"])
		container.kind = int(seed_def["kind"])
		container.tier = str(seed_def["tier"])
		container.grid_size = seed_def["grid"]
		# 概率绑定：显式给出则落盘；rarity 可引用共享 tier 表
		if seed_def.has("rarity"):
			container.rarity_weights = TIER_RARITY[str(seed_def["rarity"])].duplicate()
		if seed_def.has("category"):
			container.category_weights = seed_def["category"].duplicate()

		var container_errors: Array = container.validate()
		if not container_errors.is_empty():
			errors.append("校验失败 %s: %s" % [container_id, "；".join(container_errors)])
			continue

		# 沿用既有 UID（重复生成不漂移，外部引用稳定）
		var prev_uid := _read_resource_uid(path)
		var save_err := ResourceSaver.save(container, path)
		if save_err != OK:
			errors.append("保存失败 %s（%s）: %d" % [container_id, path, save_err])
			continue

		var uid_text := _ensure_resource_uid(path, prev_uid)
		if uid_text.is_empty():
			errors.append("UID 缺失 %s" % path)
			continue
		uid_by_string_id[container_id] = uid_text
		if not tier_index.has(container.tier):
			tier_index[container.tier] = {}
		tier_index[container.tier][StringName(container_id)] = true

	if not errors.is_empty():
		for e in errors:
			push_error(e)
		quit(1)
		return

	if _save_registry(uid_by_string_id, tier_index) != OK:
		push_error("注册表保存失败")
		quit(1)
		return
	_ensure_resource_uid(REGISTRY_PATH, _read_resource_uid(REGISTRY_PATH))

	_verify(uid_by_string_id)
	quit(0)


## 新建并保存 Yard Registry（string_id <-> UID + tier 属性索引 + 扫描规则）。
func _save_registry(uid_by_string_id: Dictionary, tier_index: Dictionary) -> Error:
	var reg = RegistryScript.new()
	reg._version = 2
	var extensions: Array[String] = []
	var restrictions: Array[StringName] = [&"ContainerData"]
	var directories: Array[String] = [DEFINITIONS_DIR]
	var rulesets: Array[Dictionary] = [{
		&"allowed_file_extensions": extensions,
		&"class_restrictions": restrictions,
		&"recursive_scan": true,
		&"scan_directories": directories,
		&"scan_regex_exclude": "",
		&"scan_regex_include": "",
	}]
	reg._scan_rulesets = rulesets

	var uids_to_ids: Dictionary[StringName, StringName] = {}
	var ids_to_uids: Dictionary[StringName, StringName] = {}
	for string_id: String in uid_by_string_id.keys():
		var uid := StringName(uid_by_string_id[string_id])
		uids_to_ids[uid] = StringName(string_id)
		ids_to_uids[StringName(string_id)] = uid
	# Registry._init 在非编辑器环境将映射字典置为只读，需整体替换
	reg._uids_to_string_ids = uids_to_ids
	reg._string_ids_to_uids = ids_to_uids

	var property_index: Dictionary[StringName, Dictionary] = {}
	property_index[&"tier"] = tier_index
	reg._property_index = property_index

	return ResourceSaver.save(reg, REGISTRY_PATH)


## 生成后自检：注册表大小 / 抽样装载 / tier 索引查询。
func _verify(uid_by_string_id: Dictionary) -> void:
	var reg = load(REGISTRY_PATH)
	var expect_size: int = uid_by_string_id.size()
	if reg == null or reg.size() != expect_size:
		push_error("自检失败：注册表条目 %s != %d" % [str(reg.size() if reg else -1), expect_size])
		return
	var wood = reg.load_entry("crate_wood")
	if wood == null or wood.display_name != "木箱" or wood.tier != "C1":
		push_error("自检失败：crate_wood 装载/字段异常")
		return
	var c1_ids: Array[StringName] = reg.filter(&"tier", "C1")
	if c1_ids.size() != 4 or not c1_ids.has("extract_heli") or not c1_ids.has("carton_paper"):
		push_error("自检失败：tier 属性索引查询异常 %s" % str(c1_ids))
		return
	var weighted = reg.load_entry("wall_safe")
	if weighted == null or weighted.rarity_weights.is_empty():
		push_error("自检失败：wall_safe 概率绑定缺失")
		return
	print("自检通过：容器注册表 %d 条；C1 档 %d 条；概率绑定容器 %d 条"
		% [reg.size(), c1_ids.size(), 6])


## 读取资源文件头部的 uid 文本；缺失返回空串。
func _read_resource_uid(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text := file.get_as_text()
	file.close()
	var first_line_end := text.find("\n")
	var header := text.substr(0, first_line_end if first_line_end != -1 else text.length())
	var uid_start := header.find("uid=\"")
	if uid_start == -1:
		return ""
	var rest := header.substr(uid_start + 5)
	return rest.substr(0, rest.find("\""))


## 确保已保存资源文件头含 uid：沿用 prefer_uid（稳定引用），否则新建并写回。
func _ensure_resource_uid(path: String, prefer_uid: String = "") -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text := file.get_as_text()
	file.close()
	var first_line_end := text.find("\n")
	var header := text.substr(0, first_line_end if first_line_end != -1 else text.length())
	var uid_start := header.find("uid=\"")
	if uid_start != -1:
		var rest := header.substr(uid_start + 5)
		return rest.substr(0, rest.find("\""))
	var new_uid := prefer_uid
	if new_uid.is_empty():
		new_uid = ResourceUID.id_to_text(ResourceUID.create_id())
	var new_header := header.substr(0, header.length() - 1) \
		+ " uid=\"%s\"]" % new_uid
	var writer := FileAccess.open(path, FileAccess.WRITE)
	writer.store_string(new_header + text.substr(header.length()))
	writer.close()
	return new_uid
