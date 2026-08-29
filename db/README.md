# FullHaul 数据库 —— 初始化 / 迁移

> 引擎：SQLite 3（嵌入式本地单文件）。Godot 侧通过 `sqlite` GDExtension 访问；
> 数据库默认落在 `user://data/fullhaul.db`（可用配置覆盖）。
> 设计详见 [`docs/database/`](../docs/database/)。

## 一键初始化

**全新建库**（等价于执行全部迁移到最新版本）：

```bash
# Godot 侧（推荐，启动时由 DatabaseInitializer 自动执行）
godot --headless --path . --quit

# 或手动用 SQLite 工具执行当前完整模式
sqlite3 fullhaul.db < db/schema.sql
```

**Godot 内自动迁移**：`DatabaseInitializer` 在启动时读取
`res://db/migrations/` 下按文件名数字序排列的迁移脚本，对每个未应用版本执行
`CREATE TABLE IF NOT EXISTS ...` 并写入 `schema_migration` 表；无需人工介入。

## 新增迁移

1. 在 `db/migrations/` 新增编号文件，如 `002_add_xxx.sql`（数字序递增）。
2. 在文件内编写 `CREATE/ALTER/...` 语句（建议 `IF NOT EXISTS` 保证幂等）。
3. `DatabaseInitializer` 会自动发现并应用，无需改动其余代码。

## 目录结构

```
db/
├── schema.sql              # 当前完整模式（只读参考 / 一键全新建库）
├── README.md               # 本文件
└── migrations/
	└── 001_initial_schema.sql   # 增量迁移 001（初始全量建表）
```

## 验证

可用任意 SQLite 工具连接 `user://data/fullhaul.db` 检查表结构，或执行：

```sql
SELECT name FROM sqlite_master WHERE type='table' ORDER BY name;
```

应为 13 张表（backpack_offer / container_state / container_tier_config /
container_type / economy_transaction / item_definition / item_instance /
player_profile / run_snapshot / safe_container_config / schema_migration /
settlement_record / warehouse_item）。
