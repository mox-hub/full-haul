## repository_provider.gd —— FullHaul 仓储提供者（基础设施层，配置切换）
##
## WORD-31 阶段2：根据配置项 `fullhaul/db/backend` 决定装配哪一套仓储实现：
##   - "memory"（默认）：内存后端（InMemoryDataStore + Memory* 仓储），
##     无需 sqlite GDExtension，可在无头测试环境直接运行；
##   - "sqlite"：SQLite 后端（DatabaseConnector + Sqlite* 仓储，WORD-30），
##     需引入 `sqlite` GDExtension 后可用。
##
## 领域层/表现层只依赖仓储接口（IConfigDataRepository 等），由本提供者在
## 组合根（main.gd）处装配具体实现并注入，符合 WORD-8 分层。

extends RefCounted
class_name RepositoryProvider


## 配置键：数据层后端
const SETTING_BACKEND := "fullhaul/db/backend"
## 后端枚举
const BACKEND_MEMORY := "memory"
const BACKEND_SQLITE := "sqlite"
## 默认后端（无头测试/默认运行可用，无需 sqlite 扩展）
const DEFAULT_BACKEND := BACKEND_MEMORY


## 解析当前配置的后端类型；未配置或非法值回退默认内存后端。
static func resolve_backend() -> String:
	var backend: Variant = ProjectSettings.get_setting(SETTING_BACKEND, DEFAULT_BACKEND)
	if backend is String and backend == BACKEND_SQLITE:
		return BACKEND_SQLITE
	return BACKEND_MEMORY


## 装配一整套仓储（按配置切换后端）。
static func create_set() -> RepositorySet:
	match resolve_backend():
		BACKEND_SQLITE:
			return _create_sqlite_set()
		_:
			return _create_memory_set()


## 内存后端：共享一个 InMemoryDataStore，四仓储共读共写。
static func _create_memory_set() -> RepositorySet:
	var store := InMemoryDataStore.new()
	store.seed_v01_defaults()
	var set := RepositorySet.new()
	set.config_data = MemoryConfigDataRepository.new(store)
	set.profile = MemoryProfileRepository.new(store)
	set.run_result = MemoryRunResultRepository.new(store)
	set.run_snapshot = MemoryRunSnapshotRepository.new(store)
	return set


## SQLite 后端：打开数据库连接并装配 Sqlite* 仓储（WORD-30 实现）。
static func _create_sqlite_set() -> RepositorySet:
	var conn := DatabaseConnector.new()
	DatabaseInitializer.new().apply_all(conn)
	var set := RepositorySet.new()
	set.config_data = SqliteConfigDataRepository.new(conn)
	set.profile = SqliteProfileRepository.new(conn)
	set.run_result = SqliteRunResultRepository.new(conn)
	set.run_snapshot = SqliteRunSnapshotRepository.new(conn)
	return set