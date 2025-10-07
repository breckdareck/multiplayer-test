@tool
class_name WeaponData
extends EquipmentData


@export var weapon_type: Constants.WeaponType
## 1: Slower, 2,3: Slow, 4: Normal, 5,6: Fast, 7,8,9,10: Faster [br]
## [b]Forumla: 100 * (20-AttackSpeed) / 16 [br]
## Example: 100 * (20-4) / 16 = 100[/b]
@export_range(1,10) var weapon_attack_speed: int = 4

var attack_speed: String:
	get:
		match weapon_attack_speed:
			1:
				return "Slower"
			2, 3:
				return "Slow"
			4:
				return "Normal"
			5, 6:
				return "Fast"
			7, 8, 9, 10:
				return "Faster"
			_: # Fallback for any unexpected value outside the range
				return "Error: Unknown Speed"
