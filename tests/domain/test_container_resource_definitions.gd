## test_container_resource_definitions.gd —— FullHaul 领域测试：容器 Resource 化定义系统（GdUnit4）
##
## 职责：
##   覆盖容器定义的 Resource 化数据链路（INV-16 单一来源）：
##   - data/containers/container_registry.tres（Yard Registry）登记完整性
##   - ContainerData 资源自身属性（种类/档位/格子）与合法性
##   - to_config_dict 兼容视图（与 container_type 表字段对齐）
##   - 概率系统绑定字段经 .tres 持久化，并真实作用于 ItemProbabilitySystem
##   - 内存后端经 ContainerResourceCatalog 装载（container_types 字典视图）
##
## 运行：
##   godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd \
##        -a res://tests/domain/test_container_resource_definitions.gd --ignoreHeadlessMode

extends GdUnitTestSuite


## [ContainerResourceCatalog] 注册表装载：3 条种子容器全部登记
func test_registry_loads_all_containers() -> void:
	var reg := ContainerResourceCatalog.load_registry()
	assert_that(reg).is_not_null()
	assert_that(reg.size()).is_equal(3)


## [ContainerData] 自身属性抽样：木箱（C1/3x3/普通容器）与撤离点（extract）
func test_container_attributes() -> void:
	var wood := ContainerResourceCatalog.load_container("crate_wood")
	assert_that(wood).is_not_null()
	assert_str(wood.display_name).is_equal("木箱")
	assert_str(wood.tier).is_equal("C1")
	assert_str(wood.kind_id()).is_equal("container")
	assert_bool(wood.is_loot_container()).is_true()
	assert_that(wood.grid_size).is_equal(Vector2i(3, 3))
	assert_array(wood.validate()).is_empty()

	var heli := ContainerResourceCatalog.load_container("extract_heli")
	assert_str(heli.kind_id()).is_equal("extract")
	assert_bool(heli.is_loot_container()).is_false()


## [ContainerData] 兼容视图：to_config_dict 与 container_type 表字段对齐
func test_config_dict_matches_container_type_table() -> void:
	var metal := ContainerResourceCatalog.load_container("crate_metal")
	var dict := metal.to_config_dict()
	assert_str(str(dict.get("type_id"))).is_equal("crate_metal")
	assert_str(str(dict.get("kind"))).is_equal("container")
	assert_str(str(dict.get("tier"))).is_equal("C3")
	assert_int(int(dict.get("grid_width"))).is_equal(4)
	assert_int(int(dict.get("grid_height"))).is_equal(4)


## [ContainerData] 概率绑定字段经 .tres 持久化（自定义权重表落盘可读回）
func test_probability_binding_roundtrip() -> void:
	var container := ContainerData.new()
	container.container_id = "test_case"
	container.display_name = "测试箱"
	container.tier = "C2"
	container.rarity_weights = {"common": 0.0, "epic": 1.0}
	container.category_weights = {"tool": 2.0}
	var path := "res://data/containers/definitions/test_case.tres"
	assert_int(ResourceSaver.save(container, path)).is_equal(OK)

	var loaded: ContainerData = ResourceLoader.load(path)
	assert_that(loaded).is_not_null()
	assert_int(int(loaded.rarity_weights.get("common", 1.0))).is_equal(0)
	assert_float(float(loaded.category_weights.get("tool", 0.0))).is_equal(2.0)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## [ContainerData] 概率绑定真实作用于物品概率系统（显式绑定优先于池内分布）
func test_binding_drives_probability_system() -> void:
	var container := ContainerResourceCatalog.load_container("crate_wood")
	assert_that(container).is_not_null()
	## 木箱种子未显式绑定（空表继承共享 tier 权重表）
	assert_dict(container.rarity_weights).is_empty()

	var bound := ContainerData.new()
	bound.rarity_weights = {"legendary": 1.0}
	var sys := ItemProbabilitySystem.new(9)
	var pool: Array = []
	for def_id: String in ["item_0115", "item_0001"]:
		var data := ItemResourceCatalog.load_item(def_id)
		var def := ItemDefinition.from_resource(data)
		pool.append(def)
	for i in 10:
		var picked: ItemDefinition = sys.pick(pool, bound.rarity_weights, bound.category_weights)
		assert_str(picked.rarity).is_equal("legendary")


## [内存后端] 经 ContainerResourceCatalog 装载并导出 container_types 字典视图
func test_memory_backend_seeds_from_registry() -> void:
	var store := InMemoryDataStore.new()
	store.seed_v01_defaults()
	assert_int(store.container_data_resources.size()).is_equal(3)
	assert_int(store.container_types.size()).is_equal(3)
	var wood_dict: Dictionary = store.container_types.get("crate_wood", {})
	assert_str(str(wood_dict.get("tier"))).is_equal("C1")
	assert_str(str(wood_dict.get("kind"))).is_equal("container")
	var repo := MemoryConfigDataRepository.new(store)
	assert_int(repo.load_container_data().size()).is_equal(3)
