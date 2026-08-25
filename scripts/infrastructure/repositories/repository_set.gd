## repository_set.gd —— FullHaul 仓储集合（基础设施层装配结果）
##
## WORD-31 阶段2：把四个领域仓储接口的实现聚合成一组，供组合根/应用层注入。
## 本类只承载「实现实例」，不承载业务逻辑；领域层/表现层不感知本类。
##
## 说明：实现类遵循代码库惯例采用「鸭子类型」（RefCounted + 同名方法），
## 不显式 implements 接口，因此此处字段以 Variant 承载，运行时按接口方法调用。

extends RefCounted
class_name RepositorySet


## 配置数据仓储（道具/藏品/容器/撤离点/背包档位/产出权重）
var config_data = null
## 局外账户仓储（货币/仓库/已选背包）
var profile = null
## 结算/事务数据仓储（存档数据）
var run_result = null
## 局内状态快照仓储（运行时数据，可选）
var run_snapshot = null