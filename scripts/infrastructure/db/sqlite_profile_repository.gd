## sqlite_profile_repository.gd —— IProfileRepository 的 SQLite 实现（基础设施层）
##
## 实现领域层 IProfileRepository：把 PlayerProfile（货币/仓库/已选背包）持久化到
## player_profile + warehouse_item 表。领域层只依赖 IProfileRepository 接口，
## 不感知本实现与数据库细节。

extends RefCounted
class_name SqliteProfileRepository



const DEFAULT_PROFILE_ID := "local"

var _conn: DatabaseConnector


func _init(conn: DatabaseConnector) -> void:
	_conn = conn
	_conn.open()


func load() -> PlayerProfile:
	var profile := PlayerProfile.new()
	var rows := _conn.query(
		"SELECT currency, selected_backpack_offer_id FROM player_profile WHERE profile_id = ?",
		[DEFAULT_PROFILE_ID]
	)
	if not rows.is_empty():
		profile.currency = int(rows[0].get("currency", 0))
		profile.selected_backpack_offer_id = str(rows[0].get("selected_backpack_offer_id", ""))
	profile.warehouse_item_ids = _load_warehouse_ids()
	return profile


func save(profile: PlayerProfile) -> void:
	_conn.execute(
		"""
		INSERT INTO player_profile (profile_id, currency, selected_backpack_offer_id)
		VALUES (?, ?, ?)
		ON CONFLICT(profile_id) DO UPDATE SET
			currency = excluded.currency,
			selected_backpack_offer_id = excluded.selected_backpack_offer_id,
			updated_at = datetime('now')
		""",
		[DEFAULT_PROFILE_ID, profile.currency, profile.selected_backpack_offer_id]
	)
	_sync_warehouse(profile.warehouse_item_ids)


func _load_warehouse_ids() -> Array:
	var ids: Array = []
	for row in _conn.query(
		"SELECT instance_id FROM warehouse_item WHERE profile_id = ? ORDER BY added_at",
		[DEFAULT_PROFILE_ID]
	):
		ids.append(str(row.get("instance_id", "")))
	return ids


## 以仓库 id 集合为准做同步（先清后插，V0.1 量小可接受）。
func _sync_warehouse(ids: Array) -> void:
	_conn.execute("DELETE FROM warehouse_item WHERE profile_id = ?", [DEFAULT_PROFILE_ID])
	for instance_id in ids:
		_conn.execute(
			"INSERT INTO warehouse_item (instance_id, profile_id, definition_id, rarity, value) VALUES (?, ?, '', '', 0)",
			[instance_id, DEFAULT_PROFILE_ID]
		)
