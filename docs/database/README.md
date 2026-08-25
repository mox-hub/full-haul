# FullHaul 系统数据库 —— 选型说明

> WORD-30（FullHaul-数据库-1：系统数据库设计与搭建）交付物之一。

## 结论

选用 **SQLite（嵌入式、本地单文件）** 作为 V0.1 系统数据库引擎；在 Godot 中通过
`sqlite`（GDExtension，Godot 4.x 社区标准 SQLite 绑定）访问，落库为单个本地
`.db` 文件。完整表结构与迁移见 [`db/schema.sql`](../../db/schema.sql) 与
[`db/migrations/`](../../db/migrations)，设计细节见
[`schema-design.md`](./schema-design.md)。

## 选型背景与约束

- **嵌入式/本地文件优先**：V0.1 为单机玩法验证，无服务器、无网络依赖；
  数据库必须是进程内、零部署的本地方案。
- **与 Godot 工程兼容**：需要在 Godot 4.7 中可读写、可被单元测试（GdUnit4
  无头模式）驱动；不引入需编译原生模块的复杂构建链路。
- **遵循 WORD-8 分层**：领域层只依赖仓储接口，不接触数据库引擎；数据库实现
  位于基础设施/数据层（`scripts/infrastructure/db/`），可被替换。

## 候选方案对比

| 方案 | 说明 | 优点 | 缺点 | 结论 |
|---|---|---|---|---|
| **SQLite（GDExtension）** | 单文件嵌入式关系库，`sqlite` GDExtension 提供 Godot API | 真正的表/索引/外键/事务；查询能力强；与 WORD-30「表结构/索引/ER」要求最贴合；数据可被外部工具导出检查 | 需引入一个 GDExtension 二进制依赖 | ✅ **选用** |
| 本地 JSON 文件 | 用 Godot `FileAccess` 读写 JSON 集合 | 零依赖、最简单、天然跨平台 | 无索引/事务/外键；一致性需手写校验；与「表/ER」语义弱 | 备选（Data 层可替换实现之一） |
| Godot Resource（.tres/.res） | 引擎内置资源序列化 | 编辑器友好 | 不便于做关系查询/索引；跨版本迁移弱 | 不选 |
| 远程/云数据库 | MySQL/Postgres/云存储 | 数据集中 | 违背嵌入式/本地优先；需部署与网络 | 不选（多人为未来方向，V0.1 不承诺） |

> 架构文档（WORD-8）§3 Data 层明确「可替换存储实现（JSON/二进制/云）」；本选型把
> **SQLite 作为 V0.1 默认实现**，同时保持仓储接口与引擎解耦——后续可无缝替换为
> JSON/云实现而不动领域层（WORD-31 阶段2 落地配置切换）。

## Godot 接入方式

1. 引入 `sqlite` GDExtension（`addons/`，Godot 4.x 兼容版本）。
2. `DatabaseConnector` 负责打开 `user://data/fullhaul.db`（可用配置项覆盖路径）。
3. `DatabaseInitializer` 在启动时执行 `db/migrations/` 下的编号迁移脚本，实现
   **一键初始化**（见 [`db/README.md`](../../db/README.md)）。
4. 领域层仓储接口（`scripts/domain/repositories/`）由基础设施层
   （`scripts/infrastructure/db/`）的 SQLite 实现装配，经依赖注入提供给领域/应用层。

## 持久化范围（与架构对齐）

V0.1 持久化范围 = **同一应用运行周期内**多局正确的局外结果（仓库/货币/背包选择）；
跨重启持久化范围、存储位置与迁移策略按 **TBD-12** 待产品决策，不在 V0.1 承诺内。
数据库文件默认落在 `user://`（运行周期内）即可满足 V0.1；跨重启能力作为未来
演进保留在迁移机制中。

## 相关文档

- [`schema-design.md`](./schema-design.md)：表结构、字段、索引、ER 关系（配置/存档/运行时三类）
- [`db/schema.sql`](../../db/schema.sql)：当前完整模式（一键全新建库）
- [`db/migrations/`](../../db/migrations)：增量迁移脚本
- [`db/README.md`](../../db/README.md)：初始化/迁移操作说明
