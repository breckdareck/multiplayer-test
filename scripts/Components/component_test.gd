class_name ComponentTest
extends Node

# This script can be attached to a node to test component integration
# Run it in the editor or in-game to see debug output

@export var test_level: int = 1
@export var test_class: ClassComponent.ClassType = ClassComponent.ClassType.SWORDSMAN

func _ready() -> void:
	# Wait a frame to ensure all components are ready
	await get_tree().process_frame
	test_component_integration()

func test_component_integration() -> void:
	print("=== Component Integration Test ===")
	
	var parent = get_parent()
	if not parent:
		print("ERROR: No parent node found!")
		return
	
	# Test Class Component
	var class_comp = parent.get_node_or_null("Class")
	if class_comp:
		print("✓ Class Component found")
		print("  Current class: %s" % class_comp.get_class_name())
		print("  Class summary: %s" % class_comp.get_class_summary())
	else:
		print("✗ Class Component not found!")
	
	# Test Stats Component
	var stats_comp = parent.get_node_or_null("Stats")
	if stats_comp:
		print("✓ Stats Component found")
		print("  Base stats - STR: %d, DEX: %d, INT: %d, VIT: %d" % [
			stats_comp.base_strength, 
			stats_comp.base_dexterity, 
			stats_comp.base_intelligence, 
			stats_comp.base_vitality
		])
		print("  Current stats - STR: %d, DEX: %d, INT: %d, VIT: %d" % [
			stats_comp.get_strength(),
			stats_comp.get_dexterity(),
			stats_comp.get_intelligence(),
			stats_comp.get_vitality()
		])
		print("  Total stats: %s" % stats_comp.get_total_stats())
		print("  Applied class bonuses: %s" % stats_comp.get_applied_class_bonuses())
	else:
		print("✗ Stats Component not found!")
	
	# Test Level Component
	var level_comp = parent.get_node_or_null("Leveling")
	if level_comp:
		print("✓ Level Component found")
		print("  Current level: %d" % level_comp.level)
		print("  Current exp: %d / %d" % [level_comp.experience, level_comp.get_exp_to_next_level()])
	else:
		print("✗ Level Component not found!")
	
	# Test Health Component
	var health_comp = parent.get_node_or_null("Health")
	if health_comp:
		print("✓ Health Component found")
		print("  Current health: %d / %d" % [health_comp.current_health, health_comp.max_health])
	else:
		print("✗ Health Component not found!")
	
	# Test Combat Component
	var combat_comp = parent.get_node_or_null("Combat")
	if combat_comp:
		print("✓ Combat Component found")
		print("  Attack map keys: %s" % combat_comp.attack_map.keys())
	else:
		print("✗ Combat Component not found!")
	
	print("=== Test Complete ===")

func test_class_change() -> void:
	print("=== Testing Class Change ===")
	var parent = get_parent()
	var class_comp = parent.get_node_or_null("Class")
	
	if class_comp:
		var original_class = class_comp.current_class
		print("Original class: %s" % class_comp.get_class_name())
		
		# Change to a different class
		var new_class = (original_class + 1) % ClassComponent.ClassType.size()
		class_comp.change_class(new_class)
		
		print("Changed to: %s" % class_comp.get_class_name())
		print("New class summary: %s" % class_comp.get_class_summary())
		
		# Check if stats were updated
		var stats_comp = parent.get_node_or_null("Stats")
		if stats_comp:
			print("Updated stats: %s" % stats_comp.get_total_stats())
	else:
		print("No Class Component found for testing!")

func test_level_up() -> void:
	print("=== Testing Level Up ===")
	var parent = get_parent()
	var level_comp = parent.get_node_or_null("Leveling")
	
	if level_comp:
		var original_level = level_comp.level
		var original_exp = level_comp.experience
		print("Original level: %d, exp: %d" % [original_level, original_exp])
		
		# Add enough exp to level up
		var exp_needed = level_comp.get_exp_to_next_level()
		level_comp.add_exp(exp_needed)
		
		print("Added %d exp, new level: %d" % [exp_needed, level_comp.level])
		
		# Check if stats were updated
		var stats_comp = parent.get_node_or_null("Stats")
		if stats_comp:
			print("Updated stats: %s" % stats_comp.get_total_stats())
	else:
		print("No Level Component found for testing!")

