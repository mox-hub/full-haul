## generate_item_data.gd —— 物品 Resource 生成工具（一次性，可重复执行）
##
## 职责：
##   读取 data/items/source/物资数据库_初版整合清单.csv（145 条），为每条
##   物品生成 data/items/definitions/item_XXXX.tres（ItemData 资源），并
##   新建/更新 data/items/item_registry.tres（Yard Registry）：
##   string_id（item_XXXX）-> 资源 UID 双向登记 + rarity/category 属性索引。
##
## 用法（本机 Godot 4.7.2 console 版）：
##   Godot_v4.7.2-stable_win64_console.exe --headless \
##     --path E:/Project/full-haul -s res://tools/generate_item_data.gd
##
## 说明：
##   - 幂等：重复执行整体覆盖重建，UID 稳定（已存在文件的 UID 优先沿用，
##     保证注册表与引用关系不漂移）。
##   - 字段映射：rarity 白/蓝/紫/金/红 -> common/uncommon/rare/epic/legendary；
##     size "WxH" -> grid_size；堆叠数量 -> max_stack；boundary -> boundary_note。

extends SceneTree

const ItemDataScript := preload("res://data/items/item_data.gd")
const RegistryScript := preload("res://addons/yard/registry.gd")

const CSV_PATH := "res://data/items/source/物资数据库_初版整合清单.csv"
const DEFINITIONS_DIR := "res://data/items/definitions"
const REGISTRY_PATH := "res://data/items/item_registry.tres"

## 源表 rarity -> ItemData.Rarity
const RARITY_MAP := {
	"白": 0, # COMMON
	"蓝": 1, # UNCOMMON
	"紫": 2, # RARE
	"金": 3, # EPIC
	"红": 4, # LEGENDARY
}

## 源表 category -> ItemData.Category
const CATEGORY_MAP := {
	"收藏品": 0, # COLLECTIBLE
	"情报文件": 1, # INTEL
	"电子设备": 2, # ELECTRONICS
	"工具": 3, # TOOL
	"医疗用品": 4, # MEDICAL
	"食品": 5, # FOOD
	"生活用品": 6, # DAILY
	"物料": 7, # MATERIAL
}


func _initialize() -> void:
	var rows := _read_csv_rows(CSV_PATH)
	if rows.is_empty():
		push_error("CSV 无数据行: %s" % CSV_PATH)
		quit(1)
		return
	print("CSV 数据行: %d" % rows.size())

	var errors: Array = []
	var uid_by_string_id: Dictionary = {}
	var rarity_index: Dictionary = {}
	var category_index: Dictionary = {}

	for row: Array in rows:
		if row.size() < 8:
			errors.append("列数不足，跳过: %s" % str(row))
			continue
		var item_id := str(row[0])
		var string_id := "item_" + item_id
		var path := "%s/item_%s.tres" % [DEFINITIONS_DIR, item_id]

		var item = ItemDataScript.new()
		item.item_id = item_id
		item.display_name = str(row[2])
		if CATEGORY_MAP.has(str(row[1])):
			item.category = CATEGORY_MAP[str(row[1])]
		else:
			errors.append("未知类别 %s（%s）" % [str(row[1]), item_id])
		if RARITY_MAP.has(str(row[3])):
			item.rarity = RARITY_MAP[str(row[3])]
		else:
			errors.append("未知品质 %s（%s）" % [str(row[3]), item_id])
		item.base_value = int(row[4])
		var size_parts := str(row[5]).split("x")
		if size_parts.size() == 2:
			item.grid_size = Vector2i(int(size_parts[0]), int(size_parts[1]))
		else:
			errors.append("尺寸格式非法 %s（%s）" % [str(row[5]), item_id])
		item.boundary_note = str(row[6])
		item.max_stack = int(row[7])

		var item_errors: Array = item.validate()
		if not item_errors.is_empty():
			errors.append("校验失败 %s: %s" % [item_id, "；".join(item_errors)])
			continue

		# 沿用既有 UID（重复生成不漂移，外部引用稳定）
		var prev_uid := _read_resource_uid(path)
		var save_err := ResourceSaver.save(item, path)
		if save_err != OK:
			errors.append("保存失败 %s（%s）: %d" % [item_id, path, save_err])
			continue

		var uid_text := _ensure_resource_uid(path, prev_uid)
		if uid_text.is_empty():
			errors.append("UID 缺失 %s" % path)
			continue
		uid_by_string_id[string_id] = uid_text
		# 属性索引（对齐 RegistryIO.rebuild_property_index 结构：值 -> {string_id: true}）
		if not rarity_index.has(item.rarity):
			rarity_index[item.rarity] = {}
		rarity_index[item.rarity][StringName(string_id)] = true
		if not category_index.has(item.category):
			category_index[item.category] = {}
		category_index[item.category][StringName(string_id)] = true

	if not errors.is_empty():
		for e in errors:
			push_error(e)
		quit(1)
		return

	var registry_prev_uid := _read_resource_uid(REGISTRY_PATH)
	var reg_err := _save_registry(uid_by_string_id, rarity_index, category_index)
	if reg_err != OK:
		push_error("注册表保存失败: %d" % reg_err)
		quit(1)
		return
	_ensure_resource_uid(REGISTRY_PATH, registry_prev_uid)

	_verify(uid_by_string_id)
	quit(0)


## 读取 CSV，跳过表头，返回数据行（每行为字段数组，已去引号/空白）。
func _read_csv_rows(path: String) -> Array:
	if not FileAccess.file_exists(path):
		push_error("CSV 不存在: %s" % path)
		return []
	var file := FileAccess.open(path, FileAccess.READ)
	var text := file.get_as_text()
	file.close()
	var rows: Array = []
	var lines := text.replace("\r\n", "\n").replace("\r", "\n").split("\n")
	var started := false
	for line in lines:
		if line.strip_edges().is_empty():
			continue
		var fields := _parse_csv_line(line)
		if not started:
			started = true # 表头
			continue
		rows.append(fields)
	return rows


## 单行 CSV 解析（处理双引号包裹字段；值内无逗号/转义引号，按源表现状）。
func _parse_csv_line(line: String) -> Array:
	var fields: Array = []
	var current := ""
	var in_quotes := false
	for i in range(line.length()):
		var ch := line[i]
		if ch == "\"":
			in_quotes = not in_quotes
		elif ch == "," and not in_quotes:
			fields.append(current.strip_edges())
			current = ""
		else:
			current += ch
	fields.append(current.strip_edges())
	return fields


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
## 返回最终生效的 "uid://..." 文本。
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
	# 生成/沿用 UID 并写回文件头（ResourceSaver 未自动嵌入时的兜底）
	var new_uid := prefer_uid
	if new_uid.is_empty():
		new_uid = ResourceUID.id_to_text(ResourceUID.create_id())
	var new_header := header.substr(0, header.length() - 1) \
		+ " uid=\"%s\"]" % new_uid
	var writer := FileAccess.open(path, FileAccess.WRITE)
	writer.store_string(new_header + text.substr(header.length()))
	writer.close()
	return new_uid


## 新建并保存 Yard Registry（string_id <-> UID 双向表 + 扫描规则 + 属性索引）。
func _save_registry(uid_by_string_id: Dictionary, rarity_index: Dictionary,
		category_index: Dictionary) -> Error:
	var reg = RegistryScript.new()
	reg._version = 2
	var extensions: Array[String] = []
	var restrictions: Array[StringName] = [&"ItemData"]
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

	var ids := uid_by_string_id.keys()
	ids.sort()
	# Registry._init 在非编辑器环境将映射字典置为只读，需整体替换为新字典
	var uids_to_ids: Dictionary[StringName, StringName] = {}
	var ids_to_uids: Dictionary[StringName, StringName] = {}
	for string_id: String in ids:
		var uid := StringName(uid_by_string_id[string_id])
		uids_to_ids[uid] = StringName(string_id)
		ids_to_uids[StringName(string_id)] = uid
	reg._uids_to_string_ids = uids_to_ids
	reg._string_ids_to_uids = ids_to_uids

	var property_index: Dictionary[StringName, Dictionary] = {}
	property_index[&"rarity"] = rarity_index
	property_index[&"category"] = category_index
	reg._property_index = property_index

	return ResourceSaver.save(reg, REGISTRY_PATH)


## 生成后自检：注册表大小 / 抽样装载 / 属性索引查询。
func _verify(uid_by_string_id: Dictionary) -> void:
	var reg = load(REGISTRY_PATH)
	var expect_size: int = uid_by_string_id.size()
	if reg == null or reg.size() != expect_size:
		push_error("自检失败：注册表条目 %s != %d" % [str(reg.size() if reg else -1), expect_size])
		return
	var first_uid: String = uid_by_string_id.get("item_0001", "")
	if not ResourceLoader.exists(first_uid):
		# UID 缓存未含新文件（首次生成后需执行 --import 重建缓存）
		print("结构自检通过：注册表 %d 条（UID 缓存待 --import 重建，跳过装载自检）" % reg.size())
		return
	var first = reg.load_entry("item_0001")
	if first == null or first.display_name != "古代能源核心" or first.rarity_id() != "legendary":
		push_error("自检失败：item_0001 装载/字段异常")
		return
	var legendary_ids: Array[StringName] = reg.filter(&"rarity", 4) # LEGENDARY
	if legendary_ids.is_empty() or not legendary_ids.has("item_0001"):
		push_error("自检失败：rarity 属性索引查询异常")
		return
	var collectible_ids: Array[StringName] = reg.filter(&"category", 0) # COLLECTIBLE
	print("自检通过：注册表 %d 条；legendary %d 条；收藏品 %d 条"
		% [reg.size(), legendary_ids.size(), collectible_ids.size()])
