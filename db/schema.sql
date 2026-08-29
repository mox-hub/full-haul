-- =====================================================================
-- FullHaul 系统数据库 —— 当前完整模式（schema.sql）
-- ---------------------------------------------------------------------
-- 用途：一次性建库/建表入口，生成当前版本的完整数据库。
--   数据库引擎：SQLite 3（嵌入式、本地单文件，与 Godot 工程兼容）。
--   落库位置：由应用运行时决定（默认 user://data/fullhaul.db，可用配置切换）。
--
-- 三类数据划分（对齐 WORD-30 设计文档 / 架构 §5、§3 Data 层）：
--   A. 配置数据（config_* / *_offer / *_tier_config）：道具/藏品/容器/撤离点
--      等静态数据，与 WORD-27 CSV 字段对齐；
--   B. 存档数据（player_* / settlement_record / economy_transaction）：玩家进度、
--      背包/仓库、结算记录，V0.1 持久化范围为同一应用运行周期内（TBD-12）；
--   C. 运行时数据（run_snapshot / container_state / item_instance）：一局内
--      状态快照，可选（用于调试/回放，非强制）。
--
-- 迁移机制：若使用增量迁移，请用 db/migrations/ 下的编号脚本；本文件仅
-- 用于全新初始化（等价于依次执行全部迁移到当前版本）。
-- =====================================================================

PRAGMA foreign_keys = ON;

-- =====================================================================
-- A. 配置数据（静态；与 WORD-27 CSV 对齐；运行时只读，由配置加载器消费）
-- =====================================================================

-- 道具 / 藏品定义（WORD-27：道具 + 藏品两张 CSV 的字段并集，category 区分）
--   definition_id : 唯一 id（WORD-27 CSV「ID」列）
--   category      : 'item' 道具 | 'collectible' 藏品
--   name          : 显示名
--   rarity        : common/uncommon/rare/epic/legendary（对应揭晓耗时，INV-16）
--   width/height  : 占格尺寸（正整数）
--   value         : 基础价值（出售/结算用）
--   stackable     : 是否可堆叠
--   effect_value  : 功能道具效果数值（WORD-27「效果数值」列；非功能道具为 NULL）
--   series        : 藏品所属系列（WORD-27「所属系列」列；道具为 NULL）
--   color_semantic: 视觉语义色（品质 HEX 为 TBD，故可空）
--   max_stack     : 最大堆叠数（1 = 不可堆叠；对齐 ItemData.max_stack）
--   boundary_note : 品质内极值备注（物资数据库 boundary 列）
--   description   : 展示描述
-- 运行期单一来源为 data/items/item_registry.tres 注册的 ItemData .tres
-- 资源（INV-16）；本表为 SQLite 后端的同构落库形态（增量列见迁移 002）。
CREATE TABLE IF NOT EXISTS item_definition (
	definition_id   TEXT PRIMARY KEY,
	category        TEXT NOT NULL CHECK (category IN ('collectible', 'intel', 'electronics', 'tool', 'medical', 'food', 'daily', 'material')),
	name            TEXT NOT NULL,
	rarity          TEXT NOT NULL CHECK (rarity IN ('common', 'uncommon', 'rare', 'epic', 'legendary')),
	width           INTEGER NOT NULL CHECK (width > 0),
	height          INTEGER NOT NULL CHECK (height > 0),
	value           INTEGER NOT NULL DEFAULT 0,
	stackable       INTEGER NOT NULL DEFAULT 0,
	effect_value    INTEGER,
	series          TEXT,
	color_semantic  TEXT,
	max_stack       INTEGER NOT NULL DEFAULT 1,
	boundary_note   TEXT,
	description     TEXT
);
-- 按稀有度/类别快速查询（配置加载与数值表生成用）
CREATE INDEX IF NOT EXISTS idx_item_definition_rarity ON item_definition (rarity);
CREATE INDEX IF NOT EXISTS idx_item_definition_category ON item_definition (category);

-- 容器 / 撤离点类型（WORD-27「撤离点配置」；架构 §5 ContainerType）
--   容器类型与 Tier 分离（INV-15）；撤离点作为特殊容器类型（kind='extract'）
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

-- 容器产出权重表（架构 §5 ContainerTierConfig；C1~C5 决定产出权重，权重合计 100%）
CREATE TABLE IF NOT EXISTS container_tier_config (
	tier          TEXT PRIMARY KEY,
	rarity_weights TEXT NOT NULL  -- JSON：{"common":60,"uncommon":25,"rare":10,"epic":4,"legendary":1}
);

-- 背包档位（架构 §5 BackpackOffer；V0.1 三档：4x4/1000、5x5/2500、6x6/5000）
CREATE TABLE IF NOT EXISTS backpack_offer (
	offer_id     TEXT PRIMARY KEY,
	display_name TEXT NOT NULL,
	price        INTEGER NOT NULL CHECK (price > 0),
	grid_width   INTEGER NOT NULL CHECK (grid_width > 0),
	grid_height  INTEGER NOT NULL CHECK (grid_height > 0)
);

-- 安全箱配置（架构 §5 SafeContainerConfig；V0.1 测试配置）
CREATE TABLE IF NOT EXISTS safe_container_config (
	id             INTEGER PRIMARY KEY CHECK (id = 1),
	grid_width     INTEGER NOT NULL DEFAULT 2,
	grid_height    INTEGER NOT NULL DEFAULT 2,
	default_owned  INTEGER NOT NULL DEFAULT 1,
	price          INTEGER NOT NULL DEFAULT 0
);

-- =====================================================================
-- B. 存档数据（玩家进度 / 仓库 / 结算记录；V0.1 持久化=同运行周期内，TBD-12）
-- =====================================================================

-- 玩家局外账户（架构 §5 PlayerProfile；货币账本 + 已选背包装载引用）
CREATE TABLE IF NOT EXISTS player_profile (
	profile_id                TEXT PRIMARY KEY,
	currency                  INTEGER NOT NULL DEFAULT 0,
	selected_backpack_offer_id TEXT,           -- 引用 backpack_offer.offer_id
	updated_at                TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_player_profile_offer
	ON player_profile (selected_backpack_offer_id);

-- 仓库物品（Profile 的 warehouseItemIds；InstanceId 全局唯一，INV-01）
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

-- 结算记录（每局结算，INV-09 幂等 / 成功失败 / 携带与安全箱物品）
CREATE TABLE IF NOT EXISTS settlement_record (
	record_id        TEXT PRIMARY KEY,
	run_id           TEXT NOT NULL,
	profile_id       TEXT NOT NULL,
	result           TEXT NOT NULL CHECK (result IN ('success', 'failure')),
	currency_before  INTEGER NOT NULL,
	currency_after   INTEGER NOT NULL,
	carried_item_ids TEXT NOT NULL DEFAULT '[]',   -- JSON 数组（撤离成功带回）
	safe_item_ids    TEXT NOT NULL DEFAULT '[]',   -- JSON 数组（失败安全箱）
	settled_at       TEXT NOT NULL DEFAULT (datetime('now')),
	UNIQUE (run_id),
	FOREIGN KEY (profile_id) REFERENCES player_profile (profile_id)
);
CREATE INDEX IF NOT EXISTS idx_settlement_profile ON settlement_record (profile_id);
CREATE INDEX IF NOT EXISTS idx_settlement_run ON settlement_record (run_id);

-- 经济事务流水（INV-12 货币守恒 / 事务防重与诊断）
CREATE TABLE IF NOT EXISTS economy_transaction (
	transaction_id TEXT PRIMARY KEY,
	profile_id     TEXT NOT NULL,
	type           TEXT NOT NULL,   -- purchase/sell/settlement/other
	amount         INTEGER NOT NULL,
	ref_id         TEXT,            -- 业务引用（如 offer_id / item instance / run_id）
	balance_before INTEGER NOT NULL,
	balance_after  INTEGER NOT NULL,
	status         TEXT NOT NULL DEFAULT 'ok',
	created_at     TEXT NOT NULL DEFAULT (datetime('now')),
	FOREIGN KEY (profile_id) REFERENCES player_profile (profile_id)
);
-- 同一业务引用的同类型事务唯一，用于防重（INV-12）
CREATE UNIQUE INDEX IF NOT EXISTS idx_transaction_dedupe
	ON economy_transaction (profile_id, type, ref_id);
CREATE INDEX IF NOT EXISTS idx_transaction_profile ON economy_transaction (profile_id);

-- =====================================================================
-- C. 运行时数据（一局内状态快照，可选；用于调试/回放，非强制）
-- =====================================================================

-- 每局快照（架构 §5 RunState；每局一实例，settled 防重复结算 INV-09）
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

-- 局内容器状态（架构 §5 ContainerState；counted 防重复计数 INV-06）
CREATE TABLE IF NOT EXISTS container_state (
	container_id      TEXT PRIMARY KEY,
	run_id            TEXT NOT NULL,
	type_id           TEXT,
	reveal_state      TEXT NOT NULL,     -- UNOPENED/MASKED/REVEALING/PARTIALLY_REVEALED/COMPLETED
	completed         INTEGER NOT NULL DEFAULT 0,
	counted           INTEGER NOT NULL DEFAULT 0,
	FOREIGN KEY (run_id) REFERENCES run_snapshot (run_id) ON DELETE CASCADE,
	FOREIGN KEY (type_id) REFERENCES container_type (type_id)
);
CREATE INDEX IF NOT EXISTS idx_container_state_run ON container_state (run_id);

-- 局内物品实例（架构 §5 ItemInstance；instanceId 唯一，同一实例只属一个位置 INV-01）
CREATE TABLE IF NOT EXISTS item_instance (
	instance_id   TEXT PRIMARY KEY,
	run_id        TEXT NOT NULL,
	definition_id TEXT NOT NULL,
	rarity        TEXT NOT NULL,
	orientation   INTEGER NOT NULL DEFAULT 0,   -- 旋转象限 0/1/2/3
	location      TEXT NOT NULL,                -- 'backpack' | 'safe' | 'dropped' | 'container'
	grid_x        INTEGER NOT NULL DEFAULT 0,
	grid_y        INTEGER NOT NULL DEFAULT 0,
	container_id  TEXT,
	FOREIGN KEY (run_id) REFERENCES run_snapshot (run_id) ON DELETE CASCADE,
	FOREIGN KEY (definition_id) REFERENCES item_definition (definition_id),
	FOREIGN KEY (container_id) REFERENCES container_state (container_id)
);
CREATE INDEX IF NOT EXISTS idx_item_instance_run ON item_instance (run_id);
CREATE INDEX IF NOT EXISTS idx_item_instance_location ON item_instance (run_id, location);

-- 迁移版本表（迁移机制维护；schema.sql 全新初始化时写入当前版本）
CREATE TABLE IF NOT EXISTS schema_migration (
	version   INTEGER PRIMARY KEY,
	applied_at TEXT NOT NULL DEFAULT (datetime('now'))
);
