## database_connector.gd —— FullHaul SQLite 数据库连接（基础设施层）
##
## 职责：封装 SQLite 连接的打开/关闭/执行，屏蔽数据库引擎细节，供仓储实现复用。
## 数据库默认落在 user://data/fullhaul.db，可用配置项 fullhaul/db/path 覆盖。
##
## 依赖：`sqlite` GDExtension（Godot 4.x SQLite 绑定），需随工程引入。
## 本文件位于基础设施层，不被领域层/表现层直接引用。

extends RefCounted
class_name DatabaseConnector


const DEFAULT_DB_PATH := "user://data/fullhaul.db"

var _db_path: String = ""
var _connection: Object = null
var _open := false


func _init(p_db_path := "") -> void:
	_db_path = p_db_path if p_db_path != "" else DEFAULT_DB_PATH


## 打开数据库（不存在则自动创建）。返回是否成功。
func open() -> bool:
	if _open:
		return true
	if _connection == null:
		_connection = ClassDB.instantiate("SQLite")
	if _connection == null:
		push_error("DatabaseConnector: sqlite GDExtension 未加载，请先引入 addons/sqlite")
		return false
	var path := ProjectSettings.globalize_path(_db_path)
	_connection.open(path)
	_connection.query("PRAGMA foreign_keys = ON")
	_open = true
	return true


## 执行一条语句（DDL/DML），可选参数绑定，返回是否成功。
func execute(sql: String, bindings: Array = []) -> bool:
	if not open():
		return false
	if bindings.is_empty():
		_connection.query(sql)
	else:
		_connection.query_with_bindings(sql, bindings)
	return true


## 执行带参数绑定的语句，返回结果行（Array[Dictionary]）；失败返回空数组。
func query(sql: String, bindings: Array = []) -> Array:
	if not open():
		return []
	var rows: Array = []
	if bindings.is_empty():
		_connection.query(sql)
	else:
		_connection.query_with_bindings(sql, bindings)
	rows = _connection.query_result if "query_result" in _connection else []
	return rows


## 返回受影响/变化的行数（用于写入校验）。
func changes() -> int:
	if _connection == null or not _open:
		return 0
	return int(_connection.changes)


## 关闭连接。
func close() -> void:
	if _connection != null and _open:
		_connection.close()
	_open = false
