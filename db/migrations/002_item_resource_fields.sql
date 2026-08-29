-- =====================================================================
-- 002_item_resource_fields.sql —— item_definition 对齐 Resource 化物品系统
-- ---------------------------------------------------------------------
-- 背景：物品定义运行期单一来源迁移为 data/items/item_registry.tres 注册的
--   ItemData .tres 资源（见 data/items/item_data.gd）；本迁移为 SQLite 后端
--   的 item_definition 表补充对应列，保持两种后端口径一致（INV-16）。
--
-- 注意：
--   1. 类别枚举已从 'item'/'collectible' 扩展为八类
--      ('collectible','intel','electronics','tool','medical','food','daily',
--      'material')。SQLite 无法直接修改 CHECK 约束，表重建迁移待 sqlite
--      后端实际启用时随数据映射一并执行；本迁移仅增量加列。
--   2. 新列与 ItemData 字段对应：max_stack（最大堆叠数）/ boundary_note
--      （品质内极值备注）/ description（展示描述）。
-- =====================================================================

ALTER TABLE item_definition ADD COLUMN max_stack INTEGER NOT NULL DEFAULT 1;
ALTER TABLE item_definition ADD COLUMN boundary_note TEXT;
ALTER TABLE item_definition ADD COLUMN description TEXT;
