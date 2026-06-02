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
	ACCURACY,     # PR 13 — appended (idx 16, NEVER insert): +% hit chance, additive in combat.gd
	EVASIONCHANCE, # PR 13 — appended (idx 17, NEVER insert): -% hit chance on incoming attacks
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

## Monster "feel" presets (MapleStory-style). Tags an enemy to a defensive/
## offensive archetype so designers pick one value instead of hand-tuning each
## stat multiplier. The actual multipliers live in EnemyData._ARCHETYPE_PRESETS;
## NONE = pure curve baseline. Per-enemy mults still stack on top for fine-tuning.
enum MonsterArchetype {
	NONE,        # curve baseline (1x everything)
	OOZE,        # slime/gel: high phys def, low magic def, soft hits
	ARMORED,     # golem/knight/stone: phys wall, decent magic resist, tanky
	SPECTRAL,    # ghost/wisp/elemental: magic wall, melts to physical
	BRUTE,       # ogre/beast: big HP, hits hard, weak to magic
	GLASS,       # imp/assassin/swarm: fragile, high damage
	JUGGERNAUT,  # elite/miniboss: tanky vs both, huge HP
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
