## container_resource_catalog.gd —— 容器 Resource 目录（基础设施层）
##
## 职责：
##   经 data/containers/container_registry.tres（Yard Registry，string_id ->
##   UID）装载全部 ContainerData 容器定义资源，为内存后端提供 Resource 化
##   配置数据源（INV-16 单一来源的注册态）。
##
## 设计要点：
##   与 ItemResourceCatalog 同构：注册表主通道 + definitions 目录扫描兜底
##   （注册表缺失/UID 缓存未建时数据源不变，仅查找策略兜底）。

extends RefCounted
class_name ContainerResourceCatalog

## 容器注册表（Yard Registry）
const REGISTRY_PATH := "res://data/containers/container_registry.tres"
## 容器定义 .tres 目录（注册表扫描规则与回退扫描均指向此处）
const DEFINITIONS_DIR := "res://data/containers/definitions"


## 加载注册表资源；不存在返回 null。
static func load_registry() -> Registry:
	if not ResourceLoader.exists(REGISTRY_PATH):
		return null
	return load(REGISTRY_PATH)


## 按 container_id（注册表 string_id，如 "crate_wood"）装载单件 ContainerData；
## 未登记或装载失败返回 null。
static func load_container(container_id: String) -> ContainerData:
	var reg := load_registry()
	if reg != null and reg.has_string_id(container_id):
		var res: Resource = reg.load_entry(container_id)
		if res is ContainerData:
			return res
	## UID 装载失败（如缓存未建）时回退目录扫描
	var all := _load_all_by_scan()
	return all.get(container_id, null)


## 装载全部 ContainerData；返回 container_id -> ContainerData。
static func load_all() -> Dictionary:
	var result: Dictionary = {}
	var reg := load_registry()
	if reg != null and reg.size() > 0:
		for string_id: StringName in reg.get_all_string_ids():
			var res: Resource = reg.load_entry(string_id)
			if res is ContainerData:
				result[res.container_id] = res
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
			if res is ContainerData:
				result[res.container_id] = res
		file_name = dir.get_next()
	dir.list_dir_end()
	return result
