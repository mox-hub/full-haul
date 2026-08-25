## run_state_store_interface.gd —— FullHaul 局内状态存储接口（领域层契约）
##
## 承载 RunState 的读写。每局一实例，经接口注入，禁止全局静态单例承载
## 运行态（审核 P1-3）。

extends RefCounted
class_name IRunStateStore


## 读取当前 RunState
func read() -> RunState:
	return null


## 写入（更新）当前 RunState
func write(state: RunState) -> void:
	pass
