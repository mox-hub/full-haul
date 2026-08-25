## test_runner.gd —— VSCode godot-unit-test-4 插件的聚合测试运行器
##
## 位置约定（mingchen3563.godot-unit-test-4 插件硬编码）：
##   插件从 <项目>/tests/test_runner.gd 读取形如 _run_suite(路径, 套件名) 的
##   双字符串字面量调用，建立「套件名 -> 测试文件」映射。本文件必须位于
##   tests/ 下，登记调用必须写成单行双字符串字面量。
##
## 调用方式（与插件一致）：
##   godot --headless --path . res://tests/test_runner.tscn
##
## 输出协议（供插件解析，亦便于人工阅读）：
##   [套件名]
##    ✓ 用例名
##    ✗ 用例名
##   Results: N passed M failed
##
## 设计：
##   - extends GdUnitTestSuite 套件：子进程经 GdUnitCmdTool 运行，剥离 ANSI
##     颜色码后解析“文件 > 用例 PASSED/FAILED”行还原逐用例结果；行级解析
##     失效时回退到 Statistics 汇总行兜底；
##   - extends SceneTree 冒烟脚本（godot-docs 约定，如有）：以 --script
##     子进程运行，透传输出，按退出码判定（0=通过）。
##   运行器最终以 0/1 退出，供插件与 CI 判定整体结果。
##
## 新增测试文件：在 _ready() 的登记表按字母序补一行 _run_suite(...)，
## 未登记的文件会执行并计入 Results，但插件测试树无法映射其结果。

extends Node

const GDUNIT_CMD_TOOL := "res://addons/gdUnit4/bin/GdUnitCmdTool.gd"

## GdUnit 用例行（ANSI 已剥离）：res://xxx.gd > test_case PASSED 93ms
const GDU_CASE := "^\\s*(res://\\S+\\.gd)\\s*>\\s*(\\w+)\\s+(PASSED|FAILED|ERROR)"
## GdUnit 汇总行：Statistics: 6 test cases | 0 errors | 0 failures | ...
const GDU_STATS := "Statistics:\\s*(\\d+) test cases \\| (\\d+) errors \\| (\\d+) failures"

var _passed := 0
var _failed := 0
var _re_case: RegEx
var _re_stats: RegEx
var _re_ansi: RegEx


func _ready() -> void:
	_re_case = RegEx.create_from_string(GDU_CASE)
	_re_stats = RegEx.create_from_string(GDU_STATS)
	_re_ansi = RegEx.create_from_string("\\x1b\\[[0-9;]*[a-zA-Z]")

	_run_suite("res://tests/application/test_run_flow_orchestrator.gd", "test_run_flow_orchestrator")
	_run_suite("res://tests/domain/test_container_search_state_machine.gd", "test_container_search_state_machine")
	_run_suite("res://tests/domain/test_domain_smoke.gd", "test_domain_smoke")
	_run_suite("res://tests/domain/test_game_config.gd", "test_game_config")
	_run_suite("res://tests/domain/test_infrastructure.gd", "test_infrastructure")
	_run_suite("res://tests/domain/test_player_profile.gd", "test_player_profile")
	_run_suite("res://tests/domain/test_run_state.gd", "test_run_state")
	_run_suite("res://tests/domain/test_top_level_state_machine.gd", "test_top_level_state_machine")
	_run_suite("res://tests/integration/test_main_flow_smoke.gd", "test_main_flow_smoke")
	_run_suite("res://tests/presentation/test_page_router.gd", "test_page_router")

	print("Results: %d passed %d failed" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


## 套件分发入口（插件按本文件中的登记字面量建套件名映射）
func _run_suite(path: String, suite_name: String) -> void:
	print("[%s]" % suite_name)
	if _is_gdunit_suite(path):
		_run_gdunit_suite(path)
	else:
		_run_smoke_script(path, suite_name)


func _is_gdunit_suite(path: String) -> bool:
	return FileAccess.get_file_as_string(path).contains("extends GdUnitTestSuite")


func _run_gdunit_suite(path: String) -> void:
	var output: Array = []
	var args: Array[String] = [
		"--headless", "--path", _project_root(),
		"-s", GDUNIT_CMD_TOOL,
		"-a", path,
		"--ignoreHeadlessMode",
	]
	var code := OS.execute(OS.get_executable_path(), args, output, true)
	var lines := _split_output(output)
	# 同一用例可能出现 STARTED/PASSED 两行，正则只匹配终态，仍按用例名去重
	var relayed := {}
	for line in lines:
		var m := _re_case.search(_strip_ansi(line))
		if m == null:
			continue
		var case_name: String = m.get_string(2)
		if relayed.has(case_name):
			continue
		relayed[case_name] = true
		if m.get_string(3) == "PASSED":
			_passed += 1
			print("  ✓ %s" % case_name)
		else:
			_failed += 1
			print("  ✗ %s" % case_name)
	if relayed.is_empty():
		# 行级解析失效（gdUnit 输出格式变更）时回退到 Statistics 汇总
		for line in lines:
			var m2 := _re_stats.search(_strip_ansi(line))
			if m2:
				var bad := int(m2.get_string(2)) + int(m2.get_string(3))
				_passed += int(m2.get_string(1)) - bad
				_failed += bad
				break
		if code != 0:
			_failed += 1
			print("  ✗ 套件运行失败（退出码 %d，详见输出）" % code)


func _run_smoke_script(path: String, suite_name: String) -> void:
	var output: Array = []
	var args: Array[String] = [
		"--headless", "--path", _project_root(),
		"--script", path,
	]
	var code := OS.execute(OS.get_executable_path(), args, output, true)
	for line in _split_output(output):
		print(_strip_ansi(line))
	if code == 0:
		_passed += 1
		print("  ✓ %s 冒烟通过（退出码 0）" % suite_name)
	else:
		_failed += 1
		print("  ✗ %s 冒烟失败（退出码 %d）" % [suite_name, code])


func _project_root() -> String:
	return ProjectSettings.globalize_path("res://")


## OS.execute 在 Windows 下可能把子进程的 CRLF 输出整段并入单个数组元素，
## 这里拼接后按 CRLF/LF 统一拆行
func _split_output(output: Array) -> PackedStringArray:
	var text := "\n".join(PackedStringArray(output))
	return text.replace("\r\n", "\n").split("\n")


func _strip_ansi(line: String) -> String:
	return _re_ansi.sub(line, "", true)
