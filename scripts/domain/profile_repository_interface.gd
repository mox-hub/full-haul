## profile_repository_interface.gd —— FullHaul 局外账户仓储接口（领域层契约）
##
## 承载 PlayerProfile（货币/仓库/背包选择）的持久化。
## V0.1 持久化范围 = 同一运行周期内（TBD-12）。

extends RefCounted
class_name IProfileRepository


## 读取局外账户
func load() -> PlayerProfile:
	return null


## 保存局外账户
func save(profile: PlayerProfile) -> void:
	pass
