## ConfigLoader —— FullHaul 全局配置加载器（Autoload 基础设施）
##
## 职责：
##   负责加载并缓存全局 GameConfig（架构 §6 切片 1、规范 6.1 单一来源）。
##   各领域/应用/表现层通过 ConfigLoader.config 读取配置，禁止各自硬编码
##   或各自读取数据文件，保证配置单一来源（INV-16）。
##
## 设计要点：
##   1. 默认从 res://data/GameConfig.gd 实例化内置配置（Resource）。
##   2. 支持从外部 JSON 覆盖（便于平衡调参），加载后执行 validate()，
##      校验失败时进入 ERROR 态，避免带错配置污染运行（规范 4.2）。
##   3. 本加载器不承载任何业务运行态。

extends Node

const DEFAULT_CONFIG_PATH := "res://data/GameConfig.gd"

## 全局配置实例（加载完成后可用）
var config: GameConfig = null

## 最近一次加载的错误信息（空串表示成功）
var last_error: String = ""


## 加载配置。默认加载内置 GameConfig；可通过 external_json_path 覆盖。
## 返回是否成功（true 表示加载且校验通过）。
func load_config(external_json_path: String = "") -> bool:
	var cfg: GameConfig = GameConfig.new()

	if external_json_path != "":
		var ok := _apply_external_json(cfg, external_json_path)
		if not ok:
			last_error = "外部配置加载失败: %s" % external_json_path
			return false

	var errors: Array = cfg.validate()
	if not errors.is_empty():
		last_error = "配置校验失败: %s" % "；".join(errors)
		return false

	config = cfg
	last_error = ""
	return true


## 从外部 JSON 覆盖内置配置（键名与 GameConfig 导出字段一致）。
func _apply_external_json(cfg: GameConfig, json_path: String) -> bool:
	if not FileAccess.file_exists(json_path):
		return false
	var file := FileAccess.open(json_path, FileAccess.READ)
	if file == null:
		return false
	var text := file.get_as_text()
	file.close()
	var parsed = JSON.parse_string(text)
	if parsed is not Dictionary:
		return false
	for key in parsed:
		if key in cfg:
			cfg.set(key, parsed[key])
	return true


## 便捷访问：获取配置（未加载时自动尝试加载）。
func get_config() -> GameConfig:
	if config == null:
		load_config()
	return config
