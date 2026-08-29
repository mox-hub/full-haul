## sqlite_config_data_repository.gd —— IConfigDataRepository 的 SQLite 实现（基础设施层）
##
## 从配置表读取道具/藏品、容器/撤离点类型、背包档位、产出权重等静态数据。
## 返回纯 Dictionary，供配置加载器/GameConfig 消费；领域层不感知数据库细节。

extends RefCounted
class_name SqliteConfigDataRepository



var _conn: DatabaseConnector


func _init(conn: DatabaseConnector) -> void:
	_conn = conn
	_conn.open()


const _ITEM_COLUMNS := "definition_id, category, name, rarity, width, height, value, stackable, effect_value, series, color_semantic, max_stack, boundary_note, description"


func load_item_definitions() -> Dictionary:
	var out := {}
	for row in _conn.query(
		"SELECT %s FROM item_definition" % _ITEM_COLUMNS
	):
		out[str(row.get("definition_id", ""))] = _row_to_dict(row)
	return out


func get_item_definition(definition_id: String) -> Dictionary:
	var rows := _conn.query(
		"SELECT %s FROM item_definition WHERE definition_id = ?" % _ITEM_COLUMNS,
		[definition_id]
	)
	if rows.is_empty():
		return {}
	return _row_to_dict(rows[0])


func load_container_types() -> Dictionary:
	var out := {}
	for row in _conn.query(
		"SELECT type_id, kind, display_name, tier, grid_width, grid_height, icon_id, map_availability FROM container_type"
	):
		out[str(row.get("type_id", ""))] = _row_to_dict(row)
	return out


func load_backpack_offers() -> Dictionary:
	var out := {}
	for row in _conn.query(
		"SELECT offer_id, display_name, price, grid_width, grid_height FROM backpack_offer"
	):
		out[str(row.get("offer_id", ""))] = _row_to_dict(row)
	return out


func load_container_tier_weights() -> Dictionary:
	var out := {}
	for row in _conn.query("SELECT tier, rarity_weights FROM container_tier_config"):
		out[str(row.get("tier", ""))] = JSON.parse_string(str(row.get("rarity_weights", "{}")))
	return out


func _row_to_dict(row: Dictionary) -> Dictionary:
	var out := {}
	for key in row:
		out[key] = row[key]
	return out
