# FullHaul 美术资产生产线（AI 生图 + 整备管线）V1

> 视觉升级决策记录（2026-08-27，grill-me 访谈锁定）：画风 = **原生平滑卡通**
> （仓库概念图即最终效果）；资产生产 = AI 生图 + 整备管线；平台 = Web 小游戏。
> 本文是整备管线的规范单一来源；工具实现在 `tools/asset_check.gd`。

## 1. 总则

- **视角**：正等距（isometric），地砖 2:1 菱形网格；室内场景光源固定**左上 45°**。
- **色板 token**（与 PixelUiKit 调色板一致，prompt 中直接引用 hex）：
  - 钢蓝主框 `#3B67C8` / 深蓝 `#284A9A` / 墙面亮蓝 `#5B85DA`
  - 奶油白面板 `#F8F1E1` / 暖沙 `#EFE0C4`
  - 警示黄 `#F4C044` / 木橙 `#CE9655`（木箱主色）/ 深木 `#8E6232`
  - 青绿（箱体/植物）`#4AB08A` / 地坪暖灰 `#D9DDE0` / 卷帘门银灰 `#D1D4D9`
- **描边**：统一深色细描边（主色加深约 40%），宽度在 2x 分辨率下 3–4px。
- **禁止**：渐变滥用、照片质感、景深模糊、文字水印、透视逃逸（一点/两点透视）。

## 2. 目录与命名

```
assets/art/
├── source_raw/          # AI 原图（gitignore，不入包不入库）
├── plates/              # 整间房间底图（含墙体/地坪/固定结构）
│   └── warehouse_plate.png
└── props/               # 叠层单体（带 alpha 透明底，可点击/可动画）
    ├── shelf_a.png      # 货架 A（含箱堆）
    ├── shelf_b.png      # 货架 B
    ├── crate_stack.png  # 地堆木箱
    ├── roll_door.png    # 卷帘门
    ├── barrels.png      # 油桶组
    ├── plants.png       # 盆栽组
    └── pallet_jack.png  # 托盘车（前景层）
```

- 一律 `snake_case.png`；**禁止中文/空格/大写**。
- `source_raw/` 原始 2K/4K 出图留存自查，不进 git（已配 `.gitignore`）。

## 3. 规格表（布局单一来源在 `warehouse_view.gd` DEFAULT_LAYOUT）

| 资产 | 显示尺寸 (px) | 生成尺寸 (px, 2x) | 层 | 交互 |
|---|---|---|---|---|
| warehouse_plate | 1080×760 | 2160×1520 | back | 无 |
| shelf_a / shelf_b | 260×300 | 520×600 | mid | hotspot→仓库弹窗 |
| crate_stack | 220×150 | 440×300 | mid | hotspot→仓库弹窗 |
| roll_door | 200×210 | 400×420 | mid | hotspot→撤离伏笔 |
| barrels | 120×140 | 240×280 | mid | 氛围 |
| plants | 110×120 | 220×240 | mid | 氛围 |
| pallet_jack | 170×110 | 340×220 | fore | 氛围（视差前景） |

- 显示尺寸为 design px；**生成一律 2x** 后降采样（降采样由整备时完成，
  入库文件即 2x 或标注过的显示尺寸，运行时 LINEAR 缩放平滑）。
- **构图留白**：plate 四角预留 20px 安全区；顶部 HUD 条（y<140）与底部
  快捷区（y>1670，全页坐标）不在 plate 构图重点内。

## 4. 生图 Prompt 模板（每次生成附在需求贴里）

**底图（整间仓库）**：

> Isometric interior of a small storage warehouse, clean flat cartoon style,
> thick soft outlines, single light source from top-left, no gradients,
> no characters, blue steel frame walls (#3B67C8) with skylight stripes,
> cream/beige wall panels (#F8F1E1), light warm-gray concrete floor (#D9DDE0)
> with yellow guide lines (#F4C044), roll-up door top-right, mezzanine loft
> top-left with stairs, straight-down 2:1 isometric grid, transparent-free
> full-bleed composition, 2160x1520.

**单体（叠层物，以货架为例）**：

> Isometric pallet rack with stacked orange cardboard boxes and teal-green
> crates, clean flat cartoon style, thick soft outline in darker wood tone,
> single light source top-left, no ground shadow baked (rendered separately
> by engine), isolated object on transparent background, straight 2:1
> isometric projection consistent with a 1080x760 warehouse plate, 520x600.

要点：
- 单体必须**透明底**（生成工具选 transparent PNG；不透明底需抠图后过检查）。
- **不要把落影画进单体**——阴影由底图或引擎承担，避免叠层穿帮。
- 每批生成后先跑 `asset_check.gd`，按不合格清单重 roll，再入正编。

## 5. 整备 checklist（人工 + 工具双重）

1. [ ] 2x 尺寸与规格表一致（工具校验）
2. [ ] 透明底 + 主体 bbox 距边 ≥4px（工具校验裁边）
3. [ ] 视角/光源/描边宽度与已有资产一致（人工对比）
4. [ ] 色板偏离度报告无大红（工具输出主色 hex 对照）
5. [ ] 命名/目录符合第 2 节（工具校验）

## 6. 工具用法

```bash
# 校验全部资产（headless，输出表格 + 不合格清单）
godot --headless --path . -s res://tools/asset_check.gd

# 视觉自查（窗口模式跑通场景并分阶段截图到 reports/）
godot --path . -s res://tools/lobby_preview.gd
```

## 7. 迭代流程

生成（source_raw）→ 整备（降采样/去底/改名）→ 落盘 plates|props →
`godot --headless --import` → `asset_check.gd` → `lobby_preview.gd` 截图对比 →
合格则提交（changelog 记一条），不合格按清单重 roll。

> 建造模式预留：`WarehouseView.apply_layout()/current_layout()` 为将来
> 「基地布置」的存/载入口；布局中的 pos/size 字段即资产摆放坐标（design px）。
