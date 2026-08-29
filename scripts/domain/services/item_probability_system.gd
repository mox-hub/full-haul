## item_probability_system.gd —— FullHaul 领域子系统：物品概率系统（Loot 域）
##
## 职责：
##   搜索系统的子系统：负责容器搜索时产出各「品质 × 类型」物品的概率——
##   从候选物品定义池中按权重加权随机抽取。权重由容器侧绑定（ContainerData
##   的 rarity_weights/category_weights），容器未自定义时回退共享 tier 权重表
##   （container_tier_config，INV-16）。
##
## 设计要点：
##   1. 纯逻辑：extends RefCounted，无节点依赖，可独立单元测试（架构原则 2）。
##   2. 随机源为内部 RandomNumberGenerator：默认随机化；可注入固定种子保证
##      测试确定性（set_seed / _init(seed_value)）。
##   3. 权重语义：
##      - rarity_weights 为空 -> 品质维度不分层（全部按 1 权重）；
##        非空时未列出的品质权重按 0 处理（即被排除，显式表即全权控制）。
##      - category_weights 同理，作用于类型维度。
##      - 物品最终权重 = rarity_weight × category_weight；权重 <= 0 的物品
##        不参与抽取；全部为 0 / 池为空时返回 null。

extends RefCounted
class_name ItemProbabilitySystem

## 内部随机源（可注种子）
var _rng := RandomNumberGenerator.new()


func _init(seed_value: int = -1) -> void:
	set_seed(seed_value)


## 注入随机种子；负值表示随机化（生产默认）。
func set_seed(seed_value: int) -> void:
	if seed_value < 0:
		_rng.randomize()
	else:
		_rng.seed = seed_value


## 按品质 × 类型权重从候选池抽取一件物品定义。
## definitions: ItemDefinition 数组（池）；rarity_weights/category_weights:
## {字符串 -> 权重}。池空或全零权重返回 null。
func pick(definitions: Array, rarity_weights: Dictionary = {},
		category_weights: Dictionary = {}) -> ItemDefinition:
	var total := 0.0
	var rolls: Array = [] # [累积权重, ItemDefinition]
	for def in definitions:
		if def == null:
			continue
		var weight := _weight_for(def, rarity_weights, category_weights)
		if weight <= 0.0:
			continue
		total += weight
		rolls.append([total, def])
	if rolls.is_empty() or total <= 0.0:
		return null
	var roll := _rng.randf() * total
	for entry in rolls:
		if roll <= entry[0]:
			return entry[1]
	return rolls[-1][1]


## 物品权重 = 品质权重 × 类型权重（未列出按 0；空表按 1）。
func _weight_for(def: ItemDefinition, rarity_weights: Dictionary,
		category_weights: Dictionary) -> float:
	return _table_weight(def.rarity, rarity_weights) \
		* _table_weight(def.category, category_weights)


func _table_weight(key: String, weights: Dictionary) -> float:
	if weights.is_empty():
		return 1.0
	return float(weights.get(key, 0.0))
