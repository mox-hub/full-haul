-- =====================================================================
-- Migration 001 —— 初始模式
-- ---------------------------------------------------------------------
-- 全量初始建表（配置/存档/运行时三类 + 迁移版本表）。
-- 该文件为增量迁移机制的第 001 版；与 db/schema.sql（当前完整模式）等价。
-- 应用方式：由 DatabaseInitializer 按 db/migrations/ 文件名数字序依次执行
--   CREATE TABLE IF NOT EXISTS，并在每份成功后向 schema_migration 写入版本号。
-- =====================================================================

PRAGMA foreign_keys = ON;

-- ---------- A. 配置数据 ----------
CREATE TABLE IF NOT EXISTS item_definition (
	definition_id   TEXT PRIMARY KEY,
	category        TEXT NOT NULL CHECK (category IN ('item', 'collectible')),
	name            TEXT NOT NULL,
	rarity          TEXT NOT NULL CHECK (rarity IN ('common', 'uncommon', 'rare', 'epic', 'legendary')),
	width           INTEGER NOT NULL CHECK (width > 0),
	height          INTEGER NOT NULL CHECK (height > 0),
	value           INTEGER NOT NULL DEFAULT 0,
	stackable       INTEGER NOT NULL DEFAULT 0,
	effect_value    INTEGER,
	series          TEXT,
	color_semantic  TEXT
);
CREATE INDEX IF NOT EXISTS idx_item_definition_rarity ON item_definition (rarity);
CREATE INDEX IF NOT EXISTS idx_item_definition_category ON item_definition (category);

CREATE TABLE IF NOT EXISTS container_type (
	type_id           TEXT PRIMARY KEY,
	kind              TEXT NOT NULL CHECK (kind IN ('container', 'extract')),
	display_name      TEXT NOT NULL,
	tier              TEXT NOT NULL,
	grid_width        INTEGER NOT NULL CHECK (grid_width > 0),
	grid_height       INTEGER NOT NULL CHECK (grid_height > 0),
	icon_id           TEXT,
	map_availability  TEXT
);
CREATE INDEX IF NOT EXISTS idx_container_type_kind ON container_type (kind);

CREATE TABLE IF NOT EXISTS container_tier_config (
	tier           TEXT PRIMARY KEY,
	rarity_weights TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS backpack_offer (
	offer_id     TEXT PRIMARY KEY,
	display_name TEXT NOT NULL,
	price        INTEGER NOT NULL CHECK (price > 0),
	grid_width   INTEGER NOT NULL CHECK (grid_width > 0),
	grid_height  INTEGER NOT NULL CHECK (grid_height > 0)
);

CREATE TABLE IF NOT EXISTS safe_container_config (
	id             INTEGER PRIMARY KEY CHECK (id = 1),
	grid_width     INTEGER NOT NULL DEFAULT 2,
	grid_height    INTEGER NOT NULL DEFAULT 2,
	default_owned  INTEGER NOT NULL DEFAULT 1,
	price          INTEGER NOT NULL DEFAULT 0
);

-- ---------- B. 存档数据 ----------
CREATE TABLE IF NOT EXISTS player_profile (
	profile_id                 TEXT PRIMARY KEY,
	currency                   INTEGER NOT NULL DEFAULT 0,
	selected_backpack_offer_id TEXT,
	updated_at                 TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_player_profile_offer
	ON player_profile (selected_backpack_offer_id);

CREATE TABLE IF NOT EXISTS warehouse_item (
	instance_id   TEXT PRIMARY KEY,
	profile_id    TEXT NOT NULL,
	definition_id TEXT NOT NULL,
	rarity        TEXT NOT NULL,
	value         INTEGER NOT NULL DEFAULT 0,
	added_at      TEXT NOT NULL DEFAULT (datetime('now')),
	FOREIGN KEY (profile_id) REFERENCES player_profile (profile_id)
		ON DELETE CASCADE,
	FOREIGN KEY (definition_id) REFERENCES item_definition (definition_id)
);
CREATE INDEX IF NOT EXISTS idx_warehouse_item_profile ON warehouse_item (profile_id);

CREATE TABLE IF NOT EXISTS settlement_record (
	record_id        TEXT PRIMARY KEY,
	run_id           TEXT NOT NULL,
	profile_id       TEXT NOT NULL,
	result           TEXT NOT NULL CHECK (result IN ('success', 'failure')),
	currency_before  INTEGER NOT NULL,
	currency_after   INTEGER NOT NULL,
	carried_item_ids TEXT NOT NULL DEFAULT '[]',
	safe_item_ids    TEXT NOT NULL DEFAULT '[]',
	settled_at       TEXT NOT NULL DEFAULT (datetime('now')),
	UNIQUE (run_id),
	FOREIGN KEY (profile_id) REFERENCES player_profile (profile_id)
);
CREATE INDEX IF NOT EXISTS idx_settlement_profile ON settlement_record (profile_id);
CREATE INDEX IF NOT EXISTS idx_settlement_run ON settlement_record (run_id);

CREATE TABLE IF NOT EXISTS economy_transaction (
	transaction_id TEXT PRIMARY KEY,
	profile_id     TEXT NOT NULL,
	type           TEXT NOT NULL,
	amount         INTEGER NOT NULL,
	ref_id         TEXT,
	balance_before INTEGER NOT NULL,
	balance_after  INTEGER NOT NULL,
	status         TEXT NOT NULL DEFAULT 'ok',
	created_at     TEXT NOT NULL DEFAULT (datetime('now')),
	FOREIGN KEY (profile_id) REFERENCES player_profile (profile_id)
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_transaction_dedupe
	ON economy_transaction (profile_id, type, ref_id);
CREATE INDEX IF NOT EXISTS idx_transaction_profile ON economy_transaction (profile_id);

-- ---------- C. 运行时数据 ----------
CREATE TABLE IF NOT EXISTS run_snapshot (
	run_id                    TEXT PRIMARY KEY,
	phase                     TEXT NOT NULL,
	remaining_match_time      INTEGER NOT NULL DEFAULT 0,
	remaining_extraction_time INTEGER NOT NULL DEFAULT 0,
	completed_container_count INTEGER NOT NULL DEFAULT 0,
	settled                   INTEGER NOT NULL DEFAULT 0,
	carried_item_ids          TEXT NOT NULL DEFAULT '[]',
	safe_item_ids             TEXT NOT NULL DEFAULT '[]',
	updated_at                TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS container_state (
	container_id      TEXT PRIMARY KEY,
	run_id            TEXT NOT NULL,
	type_id           TEXT,
	reveal_state      TEXT NOT NULL,
	completed         INTEGER NOT NULL DEFAULT 0,
	counted           INTEGER NOT NULL DEFAULT 0,
	FOREIGN KEY (run_id) REFERENCES run_snapshot (run_id) ON DELETE CASCADE,
	FOREIGN KEY (type_id) REFERENCES container_type (type_id)
);
CREATE INDEX IF NOT EXISTS idx_container_state_run ON container_state (run_id);

CREATE TABLE IF NOT EXISTS item_instance (
	instance_id   TEXT PRIMARY KEY,
	run_id        TEXT NOT NULL,
	definition_id TEXT NOT NULL,
	rarity        TEXT NOT NULL,
	orientation   INTEGER NOT NULL DEFAULT 0,
	location      TEXT NOT NULL,
	grid_x        INTEGER NOT NULL DEFAULT 0,
	grid_y        INTEGER NOT NULL DEFAULT 0,
	container_id  TEXT,
	FOREIGN KEY (run_id) REFERENCES run_snapshot (run_id) ON DELETE CASCADE,
	FOREIGN KEY (definition_id) REFERENCES item_definition (definition_id),
	FOREIGN KEY (container_id) REFERENCES container_state (container_id)
);
CREATE INDEX IF NOT EXISTS idx_item_instance_run ON item_instance (run_id);
CREATE INDEX IF NOT EXISTS idx_item_instance_location ON item_instance (run_id, location);

CREATE TABLE IF NOT EXISTS schema_migration (
	version    INTEGER PRIMARY KEY,
	applied_at TEXT NOT NULL DEFAULT (datetime('now'))
);
