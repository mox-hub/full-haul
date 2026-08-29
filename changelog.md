# 更新记录（Changelog）

本文件记录每次合入 `develop` 的变更。项目尚无版本号发布，按日期归档；后续如进入版本发布节奏，可将「未发布」区整体归档为 `[版本号] - 日期`。

## 维护约定（必读）

- **每次更新**（PR 合入或直推 `develop`）必须在「未发布」区追加条目，注明任务/PR 编号。
- CI（`changelog-check`）会校验每次 PR 与直推是否修改了本文件；确属不影响行为的改动（如纯格式化、CI 自身修复），可给 PR 打 `skip-changelog` 标签豁免。
- 条目按 `新增 / 变更 / 修复 / 文档 / 工程` 分类，一句话说清「改了什么 + 为什么」，并附任务键（WORD-NN）与 PR 编号。

## [未发布]

### 变更

- 主界面仓库场景支持滚轮缩放：WarehouseView 相机距离改为 dolly（进场推拉）× zoom（滚轮）复合驱动并统一收口到 `_apply_camera()`，新增 `set_zoom()/zoom()` 通道（单格 1.1 倍、限幅 0.55–1.7，围绕注视点等距缩放不改变视线方向）；大厅页 BaseArea 输入处理接入滚轮上/下事件驱动拉近拉远，并发布 UI_INTERACTED（scene_zoom）留痕（feat/warehouse-base-v1）
- 局内体验六项缺陷修复与搜索弹窗搬运按钮化：①背包/安全箱格子在入场后即时加载——confirm_loadout 把背包/安全箱格子初始化移到 RUN_INITIALIZED 事件之前（此前事件回调刷新拿到 null 空过），表现层阶段轮询变化时兜底补刷；②结算页带出物品数量为 0 修复——编排器在撤离落定转移「前」同时快照背包/安全箱两份清单到 RunState（状态机转移瞬间即发布终局事件，原时序 payload 恒为空），并新增带出物品单格清单（品质色描边 + 名称/价值，ScrollContainer 滚动；成功展示背包全部、失败仅安全箱物品）；③地图容器与页底背包/安全箱面板加 ScrollContainer 滚动（容器不再只能显示 6 个、背包超宽不再溢出边框）；④局内 HUD 顶栏文字由近白改深色（奶油底上不可读）；⑤搜索弹窗底部改三按钮——存放到背包 / 高价值存放到安全箱（单件价值 ≥100 判定高价值）/ 关闭，均具备功能（已揭晓物品逐件 first-fit 入目标格，未揭晓不搬、放不下留在容器并提示）；⑥telemetry_wiring 套件假配置固定单件容器（container_item_count_range 默认 (1,5) 确定性轮转使旧断言全部过期且中止后续用例，多件语义由专门套件覆盖）（feat/warehouse-base-v1）

- 全事件控制台日志：消息总线接入收口——DomainEvents 新增通用 UI_INTERACTED 交互事件（screen/action/target/detail），局内页（搜索钮/容器点击/弹窗开合/物品点击/拖拽落格）与大厅页（出击/仓库/背包/叠层物/仓库拖拽重排/出售）交互统一发布到既有事件总线；TelemetryService 新增 console_echo 开关（组合根打开，测试默认关闭不刷屏），每条事件留痕时同步打印 `[遥测][+ms] 事件摘要` 一行，领域事件（CONTAINER_OPENED/ITEM_REVEALED/ITEM_PLACED 等）与 UI 交互全量在控制台可见（feat/warehouse-base-v1）
- 搜索搬运交互改同层拖拽：搜索弹窗瘦身只含容器格（移除内部背包/安全箱画布），页底背包/安全箱面板（GridPanel）整体升级为与搜索弹窗同层级的悬浮窗——搜索弹窗在节点树序移到面板之下，打开搜索时遮罩压暗页面其余部分而面板浮在遮罩上不压暗、仍可交互，拖拽链路改为容器格 → 面板内背包/安全箱格子（落格校验与 stow 领域流程不变）（feat/warehouse-base-v1）
- 搜索弹窗重做为分步流程（蒙版 → 按品质转速揭晓 → 手动搬运）：打开容器先按物品真实占格形状加载蒙版（状态机 open 增补 sizes，蒙版从统一 1x1 改真实 w×h，只露形状不露身份的 INV-05 语义演进），逐件按 GameConfig 品质揭晓耗时转圈搜索（越稀有转越慢），揭晓后蒙版替换为 3D 物品块，玩家拖拽入背包/安全箱才落地（未搬运的揭晓物品废弃）；编排器新增 container_search_plan / reveal / finish / stow 分步用例（身份只在编排器侧计划表保管），search_and_carry_container 改走内部多件链保持旧契约兼容，容器内物品从固定 1 件扩为按 container_item_count_range 多件并 first-fit 摆入容器网格；搜索圆钮/占位编排器（未接线 Loot 域）回退占位完成计数（feat/warehouse-base-v1）
- 格子储物空间多格物品化（背包/容器/仓库全量）：新共用组件 GridBoard（w×h 自动合并大块 + 品质色框 + 3D 预览 + Godot 原生拖拽校验/放置 + 蒙版块与按转速旋转的转圈指示器），局内页底背包/安全箱与搜索弹窗内三块画布统一改 GridBoard 渲染（页底尺寸随背包档位/安全箱配置自适应缩放、ITEM_PLACED/ITEM_MOVED 事件驱动刷新），仓库出售弹窗从行列表改 8×6 格子画布（结算入库按定义尺寸 first-fit 摆位、拖拽重排、出售入口迁入 3D 大图弹窗；仓库位置为运行时状态，跨重启按入库顺序重排——位置持久化 TBD）；物品种子补 1×2/2×3/3×3 三档（净水壶/突击步枪/重型弹药箱）凑齐指定尺寸集；物品占位正方体 1m→0.5m（feat/warehouse-base-v1）
- 物品 3D 预览全量覆盖（所有藏品/搜索所得与科幻手枪同功能）：ModelPreviewView 对无模型映射（或加载失败）的物品回退品质色正方体占位（BoxMesh 兜底收编进组件、tint 随品质着色），仓库出售行与局内背包格删除「无映射走品质色条/色块」的 2D 分流，全部物品统一 3D 旋转缩略图 + 点击 360° 大图弹窗；真模型落盘后在 ITEM_MODEL_PATHS 登记即自动替换（feat/warehouse-base-v1）
- 首页仓库场景迁移为 3D 体块重建（本地模型资产）：WarehouseView 从 2D 程序化占位改为 Node3D 场景——ground 地砖 11×8 阵列 + wall 段砌两侧后墙 + box/cylinder/sphere 组合道具（货架/木箱堆/油桶/托盘车/盆栽/卷帘门贴右墙+警示灯缩放呼吸），纯色粗糙 StandardMaterial3D 保持扁平卡通；Camera3D 挂 Rig 等距取景（45° 偏航），进场推拉改 dolly 语义、拖动平移改 Rig 平移（pan_bounds 语义不变）；热点改 StaticBody3D+物理射线命中，prop_center 改返回视口投影坐标、页面点击改传视口本地坐标（修正旧版全局/本地坐标混用的偏移隐患）；模型读 assets/models/warehouse/（文件名即 cm 尺寸、原点在足迹底面中心，内部统一 ×0.01 换算；目录已入 .gitignore 作本地资产，缺文件静默跳过）；DEFAULT_LAYOUT 字典形态与 pos 语义保持不变（建造模式预留）；SceneViewport 开 own_world_3d、节点类型改 Node3D（feat/warehouse-base-v1）
- 首页仓库场景 WarehouseView 替换像素基地 BaseView（仓库基地视觉升级 M3）：「底图 plate + 叠层物 props」组装——整间房间为底图贴图，货架/卷帘门/地堆木箱等为可点击叠层物（prop_activated 信号：货架/木箱→仓库弹窗，卷帘门→撤离伏笔提示）；场景世界隔离进 BaseArea 内 SubViewport（Camera2D 进场推拉 1.06→1.0 只作用于场景视口，不污染整页 UI），Parallax2D 前后层微视差；AI 生成资产缺失时按概念图构图程序化占位，资产落盘 assets/art/ 即零改动自动替换；拖动平移由旧 ±110/±70 硬编码参数化映射相机偏移（自动 clamp 到底图边界）；layout 字典驱动 + apply_layout()/current_layout() 为建造模式预留存/载入口（feat/warehouse-base-v1）
- UI 全面换装扁平卡通风（仓库基地视觉升级 M2）：PixelUiKit 内部从「低分辨率 Image → 最近邻放大 → StyleBoxTexture」整体替换为原生 StyleBoxFlat（圆角面板 + 钢蓝描边 + 柔和落影），调色板对齐仓库概念图（奶油白面板/钢蓝框/警示黄/主行动红/青绿），方法签名与类名不变（调用方零改动）；HUD 图标（货币/生命/氧气/仓库/背包/沙漏）改为 96×96 高分程序化卡通绘制；全仓清除控件级 TEXTURE_FILTER_NEAREST（场景图标节点同步改 LINEAR，等距基地贴图保留至 M3 替换）（feat/warehouse-base-v1）
- 抽取统一弹窗骨架 PopupBase（Dim + 居中凸台面板 + 内容区，可选标题/内建关闭钮）：首页仓库出售弹窗与局内搜索弹窗两处手搓同构结构迁移完毕，对应 tscn 子树删除改为程序化构建（feat/warehouse-base-v1）
- 装载页/结算页接入 PixelUiKit 还清视觉债：确认/取消/选择/结算按钮统一圆角凸台样式（feat/warehouse-base-v1）
- 对局地图容器区内衬、主页生命/氧气条内衬由深色系改浅色主题配色；主页顶条文字（货币/角标）改暗底亮字保证可读性（feat/warehouse-base-v1）

- 渲染器迁移 gl_compatibility（仓库基地视觉升级 M1）：锁定 Web 小游戏方向（Godot 出 Web 仅支持 Compatibility），纯 2D 项目无 Mobile 依赖；project.godot 移除 d3d12 驱动指定，config/features 同步更新；场景资产自此按原生平滑卡通基准使用 LINEAR 过滤（现存像素 NEAREST 节点由后续里程碑统一清理）（feat/warehouse-base-v1）
- 内嵌中文 OFL 字体 NotoSansSC-Regular 并设为全局默认主题字体（gui/theme/custom_font）：Web 导出无系统字体回退，中文字形必须自带；附 OFL 许可文件（feat/warehouse-base-v1）
- lobby_preview 工具补拍入场帧：新增 stage0 大厅页截图（lobby_preview_home.png），此前仅覆盖对局后阶段，渲染器迁移回归缺少大厅对照（feat/warehouse-base-v1）
- WORD-40 局内页面重构（首页同款像素风）：顶部 HUD 改为三属性图标条——本局时间（沙漏+倒计时）/撤离目标（木箱+容器 x/N）/携带数（背包+件数）；撤离读条（金色进度条+剩余秒数）移至地图区底部显示；操作区改三枚圆形像素钮（搜索/撤离/完成，超时调试钮转为隐藏钩子，测试契约节点名不变）；底部新增背包+安全箱格阵（6+1 列×4 行），携带物品按品质色填入背包格；新增搜索弹窗——容器内部空间可视化（如 3x3/4x4 格），逐格扫描动画+品质色揭晓（纯表现层回放，领域侧逻辑不变），地图容器实体沿用可点击按钮契约（`%MapContainers`，完成态「已搜索」标记）（feat/lobby-home-ui）
- WORD-40 像素 UI 管线共享化：调色板/品质色/按钮与格子样式助手提升至 PixelUiKit 单一来源（epic 品质色对齐示意草图为红色系），首页与局内共用；按钮补充禁用态样式；编排器新增 backpack_item_ids() 只读访问器（局内背包格按放置顺序渲染物品品质）（feat/lobby-home-ui）
- 合并 bugfix/loadout-container-timer：入场货币校验/地图容器实体/双计时停滞修复（详见该分支条目）（feat/lobby-home-ui）

### 新增

- 物品 3D 模型预览管线（项目首个 3D 用例）：外部 OBJ 模型 HanGun（科幻手枪 LOWPOLY + 两张 BaseColor 贴图，导出缺失的 .mtl 按材质名补写）落盘 assets/models/han_gun/；新增 ModelPreviewView 组件（SubViewport 独立 World3D + 透明底 + 按 AABB 自动取景/长轴放平/慢速自转，定义→模型路径映射收编于组件 ITEM_MODEL_PATHS）与 ModelPreviewPopup 大图弹窗；仓库出售行与局内背包格对有映射的物品渲染旋转缩略图、点击弹 360° 大图，无映射物品保持品质色条；物品种子新增 item_scifi_pistol「科幻手枪」（rare/2×1/350）（feat/warehouse-base-v1）
- AI 生图资产生产线（仓库基地视觉升级 M3）：docs/art/art-pipeline.md（等距视角/左上光源/概念图色板 token 的 prompt 模板、目录与命名规范、规格表、整备 checklist、迭代流程）与 tools/asset_check.gd headless 校验工具（命名/尺寸读 WarehouseView.DEFAULT_LAYOUT 单一来源/透明底与裁边/底图不透明/色板偏离度报告，不合格退出码 1 可挂 CI）（feat/warehouse-base-v1）
- Web 导出 preset（export_presets.cfg，导出路径 build/web/，排除 assets/art/source_raw 原图目录）；本机尚未安装 Godot 导出模板，真实导出冒烟待模板安装后执行（feat/warehouse-base-v1）

### 工程

- lobby_preview 工具新增 3D 预览验证阶段：仓库种子实例（科幻手枪+电池对照）→ 拍仓库行 → 点击缩略图拍大图弹窗（lobby_preview_model_popup.png）→ 局内背包格种子后继续既有一局流程（feat/warehouse-base-v1）
- 收编未跟踪的 tests/integration/test_map_containers.gd.uid（Godot 4 uid 文件缺失会丢导入元数据）；.gitignore 排除 AI 生图原图目录 assets/art/source_raw/ 与本地导出产物 build/（feat/warehouse-base-v1）

### 修复

- 首页仓库场景占位图从平面正视恢复为 2.5D 等距俯视（用户反馈，风格保持扁平卡通不变）：plate 程序化占位重绘为 2:1 菱形地坪（地砖网格+黄色导引线+墙脚线）+ 左右后墙（钢构竖框/腰线/顶沿亮带），叠层物改按等距箱体/圆桶/贴合墙面的斜面门板绘制，物件 pos 语义改为等距地坪足迹中心并重新配平布局（货架贴近后墙、门挂右墙）；SceneViewport 开 transparent_bg 使房间浮于页面底色（原占位满幅不再遮挡视口清屏色）；修复重写时遗漏的叠层贴图 2x 降采样（缺失时整件放大一倍）；art-pipeline.md 规格表同步新尺寸（feat/warehouse-base-v1）
- 主线验证问题 1（AC-02/AC-21 入场货币校验）：移除「档案已持有档位跳过购买」路径——0 货币仍可携高价背包免检入场；入场购买改为每局一次（事务引用按 runId 唯一，跨局各自扣款、同局重复确认被 LOADOUT 阶段守卫拦截），余额不足留在装载页并提示所需价格
- 主线验证问题 2（AC-17 核心搜刮图形化）：对局地图新增按本局计划生成的可点击容器实体（数量读 GameConfig.match_container_count，容器类型读配置数据；点击即搜索该容器并携带产出，已完成容器禁用标记不重复搜索）；修复入场后局内按钮停留在禁用态的问题（RUN_INIT -> IN_RUN_LOCKED 无事件，改为表现层每帧轮询阶段变化刷新）；搜索产出实例 id 加 runId 前缀（修复第二局同容器携带被实例幂等静默拒绝）
- 主线验证问题 3（AC-10/AC-11 双计时）：RunSessionService/ExtractService 的 tick 用 int(delta) 截断帧级浮点增量（每帧 ~0.016s 全部丢失）导致总时间与撤离读条停滞——改为浮点累积满整秒再扣减，余量随局/每次撤离开始复位（INV-14）；HUD 撤离读条总量改读配置（不再硬编码 15 秒）
- 伴随测试修正：test_container_search_wiring 多局复位用例改走合法撤离流程（旧用例依赖无阶段守卫的确认入场）；test_telemetry_wiring 出售价值解析改经物品定义（解耦编排器内部实例 id 命名）

### 测试

- 新增回归用例：0 货币已持有档位入场拦截、每局重复扣款、双确认防护（test_profile_loadout_wiring）；帧级浮点计时累积与余量复位（test_run_session_service/test_extract_service）；本局容器计划与按容器搜索幂等（test_container_search_wiring/test_telemetry_wiring）；地图容器实体 GUI 可点击（tests/integration/test_map_containers.gd，全局 EventBus 进程级单例下一局一套件）

### 新增

- WORD-40 程序化像素画具 PixelArtKit 与首页基地视图 BaseView：低分辨率画布 + 整数倍最近邻放大实现像素化 2.5D，主屋/仓库棚/菜园/水塔/旗杆等元素与旗帜/信标轻量动画，纯表现无业务（feat/lobby-home-ui）
- WORD-40 开发辅助工具 tools/lobby_preview.gd：窗口模式黑盒驱动页面流程并分阶段截图到 reports/（现覆盖「入场 -> 对局 -> 搜索弹窗 -> 撤离读条」），便于 UI 迭代自查（feat/lobby-home-ui）

## [2026-08-26]

### 新增

- 切片3 Profile+Loadout：购买/选择/扣款走 Transaction 域原子性 + 初始货币档案 + 接线测试（WORD-33，PR #8）
- 切片4 RunSession：每局实例、双计时、完成数、settled（WORD-34，PR #12）
- 切片5 Item & Inventory：数据驱动物品定义 + 背包/安全箱格子 + 放置校验（WORD-35，PR #12）
- 切片6 Loot/Container：容器搜索子状态机 + 逐件揭晓幂等 + 完成计数（WORD-36，PR #12）
- 切片7 Extract：撤离锁定/解锁 + 15 秒并行计时 + 顶层状态机接线（WORD-37，PR #12）
- 切片8 Settlement+Warehouse+Transaction：成败结算/入库/出售/货币，Transaction 域保证扣款/入账原子性（WORD-38，PR #12）
- 切片9 Telemetry+表现层接场景/UI：遥测埋点 + 局内/局外界面接线 + 强制功能链闭环验证记录（WORD-39，PR #12）

### 文档

- 补录《FullHaul 产品项目规范 V0.1-baseline-02》docx（批准基线，2026-08-21）

### 工程

- 补齐 db/仓储接口脚本的 `.uid` 文件（对齐仓库既有 `.uid` 跟踪）
- 新增 `changelog.md` 与 `changelog-check` CI 校验，保证每次更新附带更新记录

## [2026-08-25]

### 新增

- 基础框架-1：工程标准化目录 + 事件总线 + 配置加载（Autoload 基础设施）（WORD-23，PR #1）
- 基础框架-2：领域层接口 + 顶层状态机骨架（域拆分）（WORD-24，PR #2）
- 基础框架-3：GdUnit4 单元测试基建 + 地基测试（WORD-25，PR #3）
- 基础页面 V0：应用编排层 + 表现层事件驱动接线；界面调整为 9:16 竖屏设计（1080×1920，短边 1080）（WORD-26，PR #4）
- 数据库设计与搭建：SQLite 选型 + 建表/迁移脚本 + 领域仓储接口 + 基础设施实现（WORD-30，PR #5→#6 链式合入）
- 数据库接入游戏系统：仓储内存/SQLite 配置切换 + 编排器接线 + 结算存档落库 + 接线测试（WORD-31，PR #7）

### 文档

- 补录《FullHaul 架构设计文档 V0.1》（返工版，源自 agent 会话快照）

## [2026-08-21]

- 初始提交（工程骨架 `a432520`）
