## test_item_resource_definitions.gd —— FullHaul 领域测试：物品 Resource 化定义系统（GdUnit4）
##
## 职责：
##   覆盖物品定义的 Resource 化数据链路（INV-16 单一来源）：
##   - data/items/item_registry.tres（Yard Registry）登记完整性（145 条物资）
##   - ItemData 资源字段与合法性（含 rarity/category 枚举映射）
##   - ItemDefinition.from_resource 领域模型映射（含旋转尺寸）
##   - to_config_dict 字典兼容视图与 from_config 回退通道一致性
##   - 注册表属性索引查询（rarity/category）
##   - ItemInventoryService 经内存后端的 Resource 优先装载链路
##
## 运行：
##   godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd \
##        -a res://tests/domain/test_item_resource_definitions.gd --ignoreHeadlessMode

extends GdUnitTestSuite


## [ItemResourceCatalog] 注册表装载：145 条物资全部登记
func test_registry_loads_all_items() -> void:
	var reg := ItemResourceCatalog.load_registry()
	assert_that(reg).is_not_null()
	assert_that(reg.size()).is_equal(145)


## [ItemResourceCatalog] 全量装载：definition_id 唯一、数据全部合法
func test_load_all_unique_and_valid() -> void:
	var all := ItemResourceCatalog.load_all()
	assert_that(all.size()).is_equal(145)
	for def_id: String in all:
		var data: ItemData = all[def_id]
		assert_that(data).is_instanceof(ItemData)
		assert_str(def_id).is_equal(data.definition_id())
		assert_array(data.validate()).is_empty()


## [ItemData] 抽样字段：item_0001 古代能源核心（红/收藏品/1x1/最大价值）
func test_item_0001_fields() -> void:
	var data := ItemResourceCatalog.load_item("item_0001")
	assert_that(data).is_not_null()
	assert_str(data.item_id).is_equal("0001")
	assert_str(data.display_name).is_equal("古代能源核心")
	assert_int(data.category).is_equal(ItemData.Category.COLLECTIBLE)
	assert_int(data.rarity).is_equal(ItemData.Rarity.LEGENDARY)
	assert_int(data.base_value).is_equal(15846000)
	assert_that(data.size()).is_equal(Vector2i.ONE)
	assert_int(data.max_stack).is_equal(1)


## [ItemData] 枚举 -> 既有字符串口径映射
func test_enum_id_mappings() -> void:
	var data := ItemResourceCatalog.load_item("item_0115") # 瓶装水 白/食品
	assert_that(data).is_not_null()
	assert_str(data.rarity_id()).is_equal("common")
	assert_str(data.category_id()).is_equal("food")
	assert_str(data.category_name()).is_equal("食品")
	var gun_core := ItemResourceCatalog.load_item("item_0001")
	assert_str(gun_core.rarity_id()).is_equal("legendary")
	assert_str(gun_core.category_id()).is_equal("collectible")


## [ItemDefinition] from_resource 映射：非正方形物品旋转后宽高互换（INV-05）
func test_from_resource_mapping_and_rotation() -> void:
	var data := ItemResourceCatalog.load_item("item_0006") # 鎏金雕像 2x3
	assert_that(data).is_not_null()
	var def := ItemDefinition.from_resource(data)
	assert_that(def).is_not_null()
	assert_str(def.definition_id).is_equal("item_0006")
	assert_str(def.rarity).is_equal("epic")
	assert_int(def.value).is_equal(348625)
	assert_that(def.size()).is_equal(Vector2i(2, 3))
	assert_that(def.rotated_size(1)).is_equal(Vector2i(3, 2))
	assert_that(def.is_valid()).is_true()


## [ItemDefinition] from_resource：null / 非法数据返回 null
func test_from_resource_rejects_invalid() -> void:
	assert_that(ItemDefinition.from_resource(null)).is_null()
	var empty := ItemData.new()
	empty.item_id = ""
	assert_that(ItemDefinition.from_resource(empty)).is_null()


## [ItemData] to_config_dict 兼容视图 -> from_config 回退通道字段一致
func test_config_dict_roundtrip_matches_resource() -> void:
	var data := ItemResourceCatalog.load_item("item_0002") # 熔金古币箱 2x2 红
	var dict := data.to_config_dict()
	assert_str(str(dict.get("definition_id"))).is_equal("item_0002")
	assert_str(str(dict.get("rarity"))).is_equal("legendary")
	assert_str(str(dict.get("category"))).is_equal("collectible")
	assert_bool(bool(dict.get("stackable"))).is_false()

	var from_res := ItemDefinition.from_resource(data)
	var from_dict := ItemDefinition.from_config(dict)
	assert_that(from_dict).is_not_null()
	assert_str(from_dict.definition_id).is_equal(from_res.definition_id)
	assert_str(from_dict.rarity).is_equal(from_res.rarity)
	assert_int(from_dict.value).is_equal(from_res.value)
	assert_that(from_dict.size()).is_equal(from_res.size())
	assert_int(from_dict.max_stack).is_equal(from_res.max_stack)


## [Registry] 属性索引查询：rarity / category 烘焙值与源表分布一致
func test_registry_property_index() -> void:
	var reg := ItemResourceCatalog.load_registry()
	assert_that(reg).is_not_null()
	assert_array(reg.filter(&"rarity", ItemData.Rarity.LEGENDARY)).has_size(7)
	assert_array(reg.filter(&"rarity", ItemData.Rarity.COMMON)).has_size(48)
	assert_array(reg.filter(&"category", ItemData.Category.COLLECTIBLE)).has_size(20)
	assert_array(reg.filter(&"category", ItemData.Category.INTEL)).has_size(15)
	assert_array(reg.filter(&"category", ItemData.Category.MATERIAL)).has_size(10)
	var hits: Array[StringName] = reg.filter(&"rarity", ItemData.Rarity.LEGENDARY)
	assert_array(hits).contains(["item_0001", "item_0036", "item_0076"])


## [ItemInventoryService] Resource 优先装载：内存后端 145 条定义可查（INV-16）
func test_service_loads_definitions_from_resources() -> void:
	var store := InMemoryDataStore.new()
	store.seed_v01_defaults()
	var repo := MemoryConfigDataRepository.new(store)
	var svc := ItemInventoryService.new(repo, null)

	assert_that(svc.get_definition("item_0001")).is_not_null()
	assert_that(svc.get_definition("item_0145")).is_not_null()
	assert_int(svc.get_definition("item_0001").max_stack).is_equal(1)
	## 非正方形定义旋转占格（切片 5 语义在 Resource 数据下保持）
	var def := svc.get_definition("item_0031") # 折叠旅行地图 3x1
	assert_that(def.size()).is_equal(Vector2i(3, 1))
	assert_that(def.rotated_size(1)).is_equal(Vector2i(1, 3))
