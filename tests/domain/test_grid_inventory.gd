## test_grid_inventory.gd —— FullHaul 领域测试：格子背包模型（GdUnit4）
##
## 职责：
##   以 GdUnit4 用例覆盖切片 5 落地的 GridInventory（架构 §5 GridInventory
##   实体、INV-04 格子合法）：
##   - 边界：不越界（边缘格/越界，AC-07）
##   - 占位：不重叠（INV-04）
##   - 合法性：尺寸为正整数
##   - 满格判定（AC-07 满包 / AC-08 满箱）
##   - 失败操作保持操作前状态（INV-04）
##   - 移动/尺寸更新（旋转后占格，INV-05）
##
## 运行：
##   godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd \
##        -a res://tests/domain/test_grid_inventory.gd --ignoreHeadlessMode

extends GdUnitTestSuite


## 便捷：新建 4x4 格子。
func _grid4() -> GridInventory:
	return GridInventory.new("g4", GridInventory.OwnerType.BACKPACK, 4, 4)


## [GridInventory] 边界：合法放置成功（含边缘格）
func test_place_within_bounds() -> void:
	var g := _grid4()
	## 顶左角
	assert_that(g.place("a", Vector2i.ONE, Vector2i.ZERO)).is_true()
	## 右下边缘格（2x2 占满 3..4 行/列）
	assert_that(g.place("b", Vector2i(2, 2), Vector2i(2, 2))).is_true()
	assert_that(g.item_count()).is_equal(2)


## [GridInventory] 边界：越界放置失败（INV-04，AC-07 边缘格）
func test_place_out_of_bounds() -> void:
	var g := _grid4()
	## 顶/左越界
	assert_that(g.can_place(Vector2i.ONE, Vector2i(-1, 0))).is_false()
	assert_that(g.can_place(Vector2i.ONE, Vector2i(0, -1))).is_false()
	## 底/右越界（尺寸超出边界）
	assert_that(g.can_place(Vector2i.ONE, Vector2i(4, 0))).is_false()
	assert_that(g.can_place(Vector2i.ONE, Vector2i(0, 4))).is_false()
	assert_that(g.can_place(Vector2i(2, 1), Vector2i(3, 0))).is_false()
	## 失败放置不产生占位（INV-04）
	assert_that(g.place("x", Vector2i.ONE, Vector2i(4, 0))).is_false()
	assert_that(g.is_empty()).is_true()


## [GridInventory] 占位：重叠放置失败（INV-04）
func test_place_overlap_rejected() -> void:
	var g := _grid4()
	assert_that(g.place("a", Vector2i(2, 2), Vector2i.ZERO)).is_true()
	## 完全重叠
	assert_that(g.can_place(Vector2i(2, 2), Vector2i.ZERO)).is_false()
	## 部分重叠（右下越界同时与 a 重叠）
	assert_that(g.can_place(Vector2i.ONE, Vector2i(1, 1))).is_false()
	## 相邻但不重叠：允许
	assert_that(g.can_place(Vector2i.ONE, Vector2i(2, 2))).is_true()
	## 失败放置不改变既有占位（INV-04）
	assert_that(g.place("b", Vector2i.ONE, Vector2i(1, 1))).is_false()
	assert_that(g.has("b")).is_false()
	assert_that(g.item_count()).is_equal(1)


## [GridInventory] 合法性：非正尺寸被拒绝
func test_invalid_size_rejected() -> void:
	var g := _grid4()
	assert_that(g.can_place(Vector2i.ZERO, Vector2i.ZERO)).is_false()
	assert_that(g.can_place(Vector2i(-1, 2), Vector2i.ZERO)).is_false()
	assert_that(g.place("x", Vector2i.ZERO, Vector2i.ZERO)).is_false()
	assert_that(g.is_empty()).is_true()


## [GridInventory] 满格判定：占满全部格子（AC-07 满包）
func test_is_full_when_all_cells_occupied() -> void:
	var g := GridInventory.new("g2", GridInventory.OwnerType.SAFE, 2, 2)
	assert_that(g.is_full()).is_false()
	## 2x2 放满一件即满
	assert_that(g.place("a", Vector2i(2, 2), Vector2i.ZERO)).is_true()
	assert_that(g.occupied_cells()).is_equal(4)
	assert_that(g.is_full()).is_true()
	## 满格后任何放置失败（INV-04）
	assert_that(g.can_place(Vector2i.ONE, Vector2i.ZERO)).is_false()


## [GridInventory] 同格移动：合法移动成功，非法（重叠/越界）保持原状（INV-04）
func test_move_keeps_state_on_failure() -> void:
	var g := _grid4()
	## a 为 2x1：放 (1,1) 占 (1,1)(2,1)
	assert_that(g.place("a", Vector2i(2, 1), Vector2i(1, 1))).is_true()
	## b 为 1x1：放 (3,3)
	assert_that(g.place("b", Vector2i.ONE, Vector2i(3, 3))).is_true()

	## 合法移动：a 移到 (1,3) 占 (1,3)(2,3)，不与 b 重叠
	assert_that(g.move("a", Vector2i(1, 3))).is_true()
	assert_that(g.position_of("a")).is_equal(Vector2i(1, 3))

	## 非法移动（与 b 重叠：a 移到 (2,3) 会占 (2,3)(3,3)）失败且保持原状
	assert_that(g.move("a", Vector2i(2, 3))).is_false()
	assert_that(g.position_of("a")).is_equal(Vector2i(1, 3))
	## 越界移动失败（a 移到 (3,3) 会越右界）
	assert_that(g.move("a", Vector2i(3, 3))).is_false()
	assert_that(g.position_of("a")).is_equal(Vector2i(1, 3))


## [GridInventory] 尺寸更新（旋转后占格）：合法更新成功，非法保持原状（INV-05）
func test_update_size_validates_in_place() -> void:
	var g := _grid4()
	assert_that(g.place("a", Vector2i(2, 1), Vector2i(1, 1))).is_true()
	## 旋转后 1x2 在 (1,1) 合法
	assert_that(g.update_size("a", Vector2i(1, 2))).is_true()
	assert_that(g.size_of("a")).is_equal(Vector2i(1, 2))
	## b 占 (3,3)；a 移到 (2,2)（占 (2,2)(2,3)）合法
	assert_that(g.place("b", Vector2i.ONE, Vector2i(3, 3))).is_true()
	assert_that(g.move("a", Vector2i(2, 2))).is_true()
	## 在 (2,2) 旋转为 2x2 会占 (2,2)(3,2)(2,3)(3,3)，与 b 重叠 -> 保持原状
	assert_that(g.update_size("a", Vector2i(2, 2))).is_false()
	assert_that(g.size_of("a")).is_equal(Vector2i(1, 2))


## [GridInventory] 移除：删除后空间释放
func test_remove_frees_cells() -> void:
	var g := _grid4()
	assert_that(g.place("a", Vector2i(2, 2), Vector2i.ZERO)).is_true()
	assert_that(g.place("b", Vector2i(2, 2), Vector2i(2, 2))).is_true()
	assert_that(g.remove("a")).is_true()
	assert_that(g.has("a")).is_false()
	assert_that(g.position_of("a")).is_equal(Vector2i(-1, -1))
	## 移除后原区域可再次放置
	assert_that(g.can_place(Vector2i(2, 2), Vector2i.ZERO)).is_true()
	## 重复移除返回 false
	assert_that(g.remove("a")).is_false()