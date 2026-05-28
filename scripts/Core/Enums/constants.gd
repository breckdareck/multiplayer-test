class_name Constants 

enum ItemRarity {
	COMMON,
	UNCOMMON,
	RARE,
	EPIC,
	LEGENDARY,
}

# ClassType now semantically means "weapon discipline" — the starting weapon
# family a character chose. Enum container kept named ClassType to keep PR 1's
# diff small (rename of the container is deferred). Int values are stable, so
# existing saves persisting the old SWORDSMAN/MAGE/ARCHER/ROGUE positions still
# resolve to the new SWORD/STAFF/BOW/DAGGER members.
enum ClassType {
	SWORD,       # was SWORDSMAN
	BOW,         # was ARCHER
	STAFF,       # was MAGE
	DAGGER,      # was ROGUE
	BEGINNER,
	# Advanced disciplines (job advancement at level 30) — PR 10 will rework these.
	CRUSADER,    # Sword → Crusader
	RANGER,      # Bow → Ranger
	ARCHMAGE,    # Staff → Archmage
	ASSASSIN,    # Dagger → Assassin
}

enum ItemType {
	ANY,
	EQUIPMENT,
	CONSUMABLE,
	MATERIAL,
}

enum StatType {
	STRENGTH,
	INTELLIGENCE,
	DEXTERITY,
	LUCK,
	HEALTH,
	MANA,
	HPREGEN,
	MPREGEN,
	DEFENSE,
	MAGICDEFENSE,
	CRITCHANCE,
	CRITDAMAGE,
	WEAPONATTACK,
	MAGICATTACK,
	KNOCKBACKRESIST,
	CONSTITUTION, # PR 7 — appended (idx 15, NEVER insert): attribute → Max HP + HP regen
}

enum EquipmentType {
	ARMOR,
	WEAPON,
}

enum ArmorType {
	HEAD,
	CHEST,
	LEGS,
	FEET,
}

enum WeaponType {
	SWORD,
	BOW,
	STAFF,
	DAGGER,
}

enum AttackType {
	MELEE,
	RANGED,
	MAGIC,
}

enum TargetType {
	SELF,
	ENEMY,
	ALLY,
	GROUND,
	NONE,
}

enum AbilityType {
	ACTIVE,
	PASSIVE,
}
