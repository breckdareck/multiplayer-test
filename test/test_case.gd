# Base class for the lightweight headless unit-test harness.
# Test suites do `extends "res://test/test_case.gd"` and define methods named
# `test_*`. The runner (test/run_tests.gd) instantiates one fresh suite per
# test method, calls `before_each()`, runs the method, then reads `failures`.
# No global class_name on purpose — keeps the project's class namespace clean.
extends RefCounted

var failures: Array[String] = []
var assertion_count: int = 0

## Override in a suite for per-test setup.
func before_each() -> void:
	pass

func fail(msg: String) -> void:
	failures.append(msg)

func assert_true(cond: bool, msg: String = "") -> void:
	assertion_count += 1
	if not cond:
		failures.append("assert_true failed. %s" % msg)

func assert_false(cond: bool, msg: String = "") -> void:
	assertion_count += 1
	if cond:
		failures.append("assert_false failed. %s" % msg)

func assert_eq(actual, expected, msg: String = "") -> void:
	assertion_count += 1
	if actual != expected:
		failures.append("assert_eq failed: expected <%s> got <%s>. %s" % [str(expected), str(actual), msg])

func assert_ne(actual, unexpected, msg: String = "") -> void:
	assertion_count += 1
	if actual == unexpected:
		failures.append("assert_ne failed: did not expect <%s>. %s" % [str(unexpected), msg])

## Float comparison with an absolute tolerance.
func assert_almost_eq(actual: float, expected: float, eps: float, msg: String = "") -> void:
	assertion_count += 1
	if absf(actual - expected) > eps:
		failures.append("assert_almost_eq failed: expected <%s> +/- <%s> got <%s>. %s" % [str(expected), str(eps), str(actual), msg])

func assert_null(value, msg: String = "") -> void:
	assertion_count += 1
	if value != null:
		failures.append("assert_null failed: got <%s>. %s" % [str(value), msg])

func assert_not_null(value, msg: String = "") -> void:
	assertion_count += 1
	if value == null:
		failures.append("assert_not_null failed. %s" % msg)
