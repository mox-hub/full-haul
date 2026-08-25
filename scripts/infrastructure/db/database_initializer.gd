## database_initializer.gd —— FullHaul 数据库初始化器（基础设施层）
##
## 职责：一键初始化数据库 —— 建库并应用 db/migrations/ 下所有未应用的迁移。
## 迁移脚本按文件名数字序执行（001_*.sql, 002_*.sql ...），每份成功后向
## schema_migration 写入版本号；已应用版本跳过（幂等）。
##
## 位置：db/migrations/ 需随工程打包；本文件位于基础设施层。

extends RefCounted
class_name DatabaseInitializer


const MIGRATIONS_DIR := "res://db/migrations/"


## 对给定连接执行全量迁移，返回本次新应用的数量。
func apply_all(conn: DatabaseConnector) -> int:
	var applied := 0
	if not conn.open():
		push_error("DatabaseInitializer: 无法打开数据库连接")
		return 0
	# 确保迁移版本表存在
	conn.execute("""
		CREATE TABLE IF NOT EXISTS schema_migration (
			version INTEGER PRIMARY KEY,
			applied_at TEXT NOT NULL DEFAULT (datetime('now'))
		)
	""")
	var known := _applied_versions(conn)
	for path in _list_migrations():
		var version := _parse_version(path)
		if version <= 0 or known.has(version):
			continue
		var sql := FileAccess.get_file_as_string(path)
		if conn.execute(sql):
			conn.execute("INSERT OR IGNORE INTO schema_migration (version) VALUES (%d)" % version)
			applied += 1
	return applied


func _applied_versions(conn: DatabaseConnector) -> Dictionary:
	var out := {}
	for row in conn.query("SELECT version FROM schema_migration"):
		out[int(row.get("version", 0))] = true
	return out


## 列出 db/migrations/ 下按文件名排序的 .sql 文件（res:// 路径）。
func _list_migrations() -> Array:
	var out: Array = []
	var dir := DirAccess.open(MIGRATIONS_DIR)
	if dir == null:
		return out
	dir.list_dir_begin()
	var files: Array = []
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".sql"):
			files.append(file_name)
		file_name = dir.get_next()
	dir.list_dir_end()
	files.sort()
	for f in files:
		out.append(MIGRATIONS_DIR + f)
	return out


## 从文件名解析版本号（如 "001_initial_schema.sql" -> 1）。
func _parse_version(file_name: String) -> int:
	var base := file_name.get_file().get_basename()
	var digits := ""
	for c in base:
		if c.is_valid_int():
			digits += c
		else:
			break
	return int(digits) if digits != "" else -1
