## config_loader_interface.gd —— FullHaul 配置加载接口（领域层契约）
##
## 领域层通过本接口读取配置，保证配置单一来源（INV-16）。

extends RefCounted
class_name IConfigLoader


## 返回 GameConfig；未加载时返回 null
func get_config() -> GameConfig:
	return null
