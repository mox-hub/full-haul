## GameConfig —— FullHaul 全局游戏配置（数据驱动单一来源）
##
## 职责：
##   承载 V0.1 最小语义实体的所有平衡/内容/测试参数（架构 §5、规范 6.1）。
##   作为配置的「单一来源」，核心算法与 UI 一律读取本配置，不硬编码数值
##   （INV-16）。
##
## 范围约束：
##   只保留 V0.1 功能链内实体（架构 §5、审核 P2-2）。战斗/AI/任务/社交/成长
##   等未来方向占位不得在此建模。
##
## 说明：此处数值来自架构文档 §5 的推荐基线。若与规范/产品最新决策冲突，
## 以最新明确指令为准；TBD 项（如品质 HEX）不得私自补默认值。

extends Resource
class_name GameConfig

## ---- 核心数值（架构 §5 GameConfig 字段）----

## 一局总时长（秒）
@export var match_duration := 180

## 撤离读条时长（秒）
@export var extraction_duration := 15

## 撤离解锁所需完成容器数
@export var required_completed_containers := 5

## 每局地图生成的可搜索容器数（AC-17 核心搜刮图形化；不少于解锁阈值，
## 供「第 N 个容器」类验收路径可测）。容器在地图场随机刷新（类型+位置），
## 长按拖动平移地图查看全部。
@export var match_container_count := 9

## 初始货币
@export var initial_currency := 100000

## 品质 -> 揭晓耗时（秒）。V0.1 暂定：0.5/1/2/3/5
@export var rarity_reveal_durations: Dictionary = {
	"common": 0.5,
	"uncommon": 1.0,
	"rare": 2.0,
	"epic": 3.0,
	"legendary": 5.0,
}

## 揭晓翻转动画时长（秒，视觉层）
@export var reveal_flip_duration := 0.3

## 基础格子尺寸（像素，视觉层）
@export var base_grid_cell_size := 64

## 容器内物品数量范围 [min, max]
@export var container_item_count_range := Vector2i(1, 5)


## ---- 背包档位（架构 §5 BackpackOffer）----
## offerId -> { name, price, gridWidth, gridHeight }
@export var backpack_offers: Dictionary = {
	"backpack_4x4": {"name": "4x4 背包", "price": 1000, "grid_width": 4, "grid_height": 4},
	"backpack_5x5": {"name": "5x5 背包", "price": 2500, "grid_width": 5, "grid_height": 5},
	"backpack_6x6": {"name": "6x6 背包", "price": 5000, "grid_width": 6, "grid_height": 6},
}


## ---- 安全箱配置（架构 §5 SafeContainerConfig）----
@export var safe_container := {
	"grid_width": 2,
	"grid_height": 2,
	"default_owned": true,
	"price": 0,
}


## ---- 视觉配置（架构 §5 VisualConfig；竖屏 9:16，短边 1080）----
@export var design_width := 1080
@export var design_height := 1920


## 获取指定品质的揭晓耗时（秒）。
func get_reveal_duration(rarity: String) -> float:
	return rarity_reveal_durations.get(rarity, 1.0)


## 获取指定背包档位配置；不存在时返回空 Dictionary。
func get_backpack_offer(offer_id: String) -> Dictionary:
	return backpack_offers.get(offer_id, {})


## 基础校验：所有背包档位价格与格数必须为正整数（供配置加载后调用）。
func validate() -> Array:
	## 返回错误信息列表；空数组表示通过
	var errors: Array = []
	if match_duration <= 0:
		errors.append("match_duration 必须为正整数")
	if extraction_duration <= 0:
		errors.append("extraction_duration 必须为正整数")
	if required_completed_containers <= 0:
		errors.append("required_completed_containers 必须为正整数")
	if match_container_count <= 0:
		errors.append("match_container_count 必须为正整数")
	for offer_id in backpack_offers:
		var offer: Dictionary = backpack_offers[offer_id]
		if offer.get("price", 0) <= 0:
			errors.append("背包档位 %s price 必须为正整数" % offer_id)
		if offer.get("grid_width", 0) <= 0 or offer.get("grid_height", 0) <= 0:
			errors.append("背包档位 %s 格数必须为正整数" % offer_id)
	return errors
