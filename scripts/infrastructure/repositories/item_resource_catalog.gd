## item_resource_catalog.gd —— 物品 Resource 目录（基础设施层）
##
## 职责：
##   经 data/items/item_registry.tres（Yard Registry，string_id -> UID）装载
##   全部 ItemData 物品定义资源，为内存后端提供 Resource 化配置数据源
##   （INV-16 单一来源的注册态）。
##
## 设计要点：
##   1. 注册表只存 UID 不存数据：按需 load 单件（load_item），或整表装载
##      （load_all）。
##   2. 注册表缺失/为空/UID 缓存未建时，回退扫描 definitions 目录直接装载
##      同一批 .tres（数据源不变，仅查找策略兜底），保证无头/CI 环境可用。

extends RefCounted
class_name ItemResourceCatalog

## 物品注册表（Yard Registry）
const REGISTRY_PATH := "res://data/items/item_registry.tres"
## 物品定义 .tres 目录（注册表扫描规则与回退扫描均指向此处）
const DEFINITIONS_DIR := "res://data/items/definitions"


## 加载注册表资源；不存在返回 null。
static func load_registry() -> Registry:
	if not ResourceLoader.exists(REGISTRY_PATH):
		return null
	return load(REGISTRY_PATH)


## 按 definition_id（注册表 string_id，如 "item_0001"）装载单件 ItemData；
## 未登记或装载失败返回 null。
static func load_item(definition_id: String) -> ItemData:
	var reg := load_registry()
	if reg != null and reg.has_string_id(definition_id):
		var res: Resource = reg.load_entry(definition_id)
		if res is ItemData:
			return res
	## UID 装载失败（如缓存未建）时回退目录扫描
	var all := _load_all_by_scan()
	return all.get(definition_id, null)


## 装载全部 ItemData；返回 definition_id -> ItemData。
static func load_all() -> Dictionary:
	var result: Dictionary = {}
	var reg := load_registry()
	if reg != null and reg.size() > 0:
		for string_id: StringName in reg.get_all_string_ids():
			var res: Resource = reg.load_entry(string_id)
			if res is ItemData:
				result[res.definition_id()] = res
	if result.is_empty():
		result = _load_all_by_scan()
	return result


## 回退：直接扫描 definitions 目录装载（不依赖 UID 缓存）。
static func _load_all_by_scan() -> Dictionary:
	var result: Dictionary = {}
	var dir := DirAccess.open(DEFINITIONS_DIR)
	if dir == null:
		return result
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".tres"):
			var res: Resource = load(DEFINITIONS_DIR + "/" + file_name)
			if res is ItemData:
				result[res.definition_id()] = res
		file_name = dir.get_next()
	dir.list_dir_end()
	return result
