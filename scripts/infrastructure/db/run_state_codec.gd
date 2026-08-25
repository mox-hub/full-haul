## run_state_codec.gd —— RunState 阶段枚举与字符串互转（基础设施层）
##
## RunState.phase 为领域层枚举；数据库以字符串存储阶段名。本工具在基础设施层
## 提供双向映射，避免在领域层引入字符串序列化依赖（保持领域层纯逻辑）。

extends RefCounted
class_name RunStateCodec


## RunState.Phase 枚举名 -> 阶段字符串（用于落库）。
static func phase_to_string(phase: int) -> String:
	return RunState.Phase.keys()[phase]


## 阶段字符串 -> RunState.Phase 枚举（未知值回退 RUN_INIT）。
static func phase_from_string(text: String) -> int:
	var idx := RunState.Phase.values().find(text)
	if idx == -1:
		return RunState.Phase.RUN_INIT
	return idx
