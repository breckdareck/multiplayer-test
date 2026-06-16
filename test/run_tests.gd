# Headless unit-test runner. No third-party dependency.
#
# Run from the project root:
#   <godot> --headless --path . --script res://test/run_tests.gd
#
# (or use test/run_tests.bat). Exit code is 0 when every test passes, 1 when
# any test fails — so CI can gate on it.
#
# Tests run on the first processed frame (not in _initialize) so autoload
# singletons (ResourceManager, BotManager, ...) have finished their _ready and
# are fully populated — the AbilityComponent suite depends on that.
extends SceneTree

const SUITES: Array[String] = [
	"res://test/ability/test_ability_scaling_formula.gd",
	"res://test/ability/test_ability_scaling_data.gd",
	"res://test/ability/test_ability_level_data.gd",
	"res://test/ability/test_ability_data.gd",
	"res://test/ability/test_ability_resources.gd",
	"res://test/ability/test_ability_upgrades.gd",
	"res://test/ability/test_status_tags.gd",
	"res://test/ability/test_duo_nodes.gd",
	"res://test/ability/test_finisher_amp.gd",
	"res://test/ability/test_pairtest_loadouts.gd",
	"res://test/ability/test_pairtest_pipeline.gd",
	"res://test/ability/test_ability_component.gd",
	"res://test/boss/test_boss_phases.gd",
	"res://test/boss/test_boss_attack_data.gd",
	"res://test/enemy/test_spawn_capacity.gd",
	"res://test/ability/test_respec_economy.gd",
	"res://test/bot/test_bot_spending.gd",
]

var _ran := false

func _process(_delta: float) -> bool:
	if _ran:
		return true
	_ran = true
	var any_failed := _run_all()
	quit(1 if any_failed else 0)
	return true

## Runs every suite. Returns true if any test failed.
func _run_all() -> bool:
	var total: int = 0
	var passed: int = 0
	var failed_names: Array[String] = []

	print("\n========== Ability unit tests ==========")
	for suite_path in SUITES:
		var script: GDScript = load(suite_path)
		var suite_name: String = suite_path.get_file().trim_suffix(".gd")
		if script == null:
			print("  [LOAD FAIL] %s" % suite_path)
			failed_names.append("%s (failed to load)" % suite_name)
			total += 1
			continue

		print("\n-- %s --" % suite_name)
		# get_script_method_list returns only methods declared in this script,
		# so inherited asserts / before_each are excluded automatically.
		var suite_test_count := 0
		for method_info in script.get_script_method_list():
			var method_name: String = method_info.name
			if not method_name.begins_with("test_"):
				continue

			suite_test_count += 1
			total += 1
			var instance = script.new()  # fresh instance per test for isolation
			instance.before_each()
			instance.callv(method_name, [])

			# A genuine pass has no failures AND ran at least one assertion. Zero
			# assertions usually means the test errored out before asserting (a
			# runtime error in setup), so treat that as a failure rather than a
			# silent false-positive pass.
			if instance.failures.is_empty() and instance.assertion_count > 0:
				passed += 1
				print("  [PASS] %s" % method_name)
			else:
				failed_names.append("%s::%s" % [suite_name, method_name])
				print("  [FAIL] %s" % method_name)
				if instance.assertion_count == 0:
					print("         (no assertions ran — test errored or is empty)")
				for failure in instance.failures:
					print("         %s" % failure)

		# A suite that loaded but exposes no test_ methods is almost always a
		# parse error in the suite (the broken script still loads non-null) or an
		# empty file — either way it must not pass silently.
		if suite_test_count == 0:
			total += 1
			failed_names.append("%s (no tests found — parse error or empty)" % suite_name)
			print("  [SUITE ERROR] no test_ methods found (parse error or empty suite)")

	print("\n========================================")
	print("  %d / %d passed" % [passed, total])
	if not failed_names.is_empty():
		print("  FAILED:")
		for name in failed_names:
			print("    - %s" % name)
	print("========================================\n")

	return not failed_names.is_empty()
