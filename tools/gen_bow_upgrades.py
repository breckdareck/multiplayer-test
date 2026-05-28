import os

BASE = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                    "resources", "Abilities", "Bow", "Upgrades")
SCRIPT_UID = "uid://baupgr1sword3"

TEMPLATE = '''[gd_resource type="Resource" script_class="AbilityUpgradeData" load_steps=2 format=3 uid="{uid}"]

[ext_resource type="Script" uid="{script_uid}" path="res://scripts/Resources/AbilitySystem/AbilityUpgradeData.gd" id="1_aud"]

[resource]
script = ExtResource("1_aud")
upgrade_id = "{upgrade_id}"
upgrade_name = "{upgrade_name}"
description = "{description}"
point_cost = {point_cost}
tier = {tier}
variant_group = "{variant_group}"
effect_key = "{effect_key}"
magnitude = {magnitude}
'''

# (filename, uid, upgrade_id, name, desc, point_cost, tier, variant_group, effect_key, magnitude)
UPGRADES = [
    # Split Shot (sps) - starter builder
    ("U_SPS_SwiftNock.tres", "uid://bowu_sps1_swiftnock", "sps_t1_swift_nock", "Swift Nock",
     "Reduces Split Shot's cooldown by 0.5 seconds.", 1, 1, "", "cooldown_flat_reduction", "0.5"),
    ("U_SPS_WideSpread.tres", "uid://bowu_sps2_widespread", "sps_t2_wide_spread", "Wide Spread",
     "Split Shot strikes +1 additional enemy.", 1, 2, "", "bonus_targets", "1.0"),
    ("U_SPS_BarbedTips.tres", "uid://bowu_sps3_barbedtips", "sps_t3_barbed_tips", "Barbed Tips",
     "Split Shot deals +45% damage.", 2, 3, "sps_shot_variant", "bonus_damage_mult", "0.45"),
    ("U_SPS_Volley.tres", "uid://bowu_sps4_volley", "sps_t3_volley", "Volley",
     "Split Shot fires +1 additional arrow per cast.", 2, 3, "sps_shot_variant", "bonus_hits", "1.0"),
    ("U_SPS_PiercingShot.tres", "uid://bowu_sps5_piercingshot", "sps_t3_piercing_shot", "Piercing Shot",
     "Split Shot's arrows punch through +2 additional enemies.", 2, 3, "sps_shot_variant", "bonus_targets", "2.0"),

    # Skyfall (sky) - AOE
    ("U_SKY_WideFall.tres", "uid://bowu_sky1_widefall", "sky_t1_wide_fall", "Wide Fall",
     "Skyfall rains down on +2 additional enemies.", 1, 1, "", "bonus_targets", "2.0"),
    ("U_SKY_HeavyVolley.tres", "uid://bowu_sky2_heavyvolley", "sky_t2_heavy_volley", "Heavy Volley",
     "Skyfall deals +25% damage.", 1, 2, "", "bonus_damage_mult", "0.25"),
    ("U_SKY_Torrent.tres", "uid://bowu_sky3_torrent", "sky_t3_torrent", "Torrent",
     "Skyfall blankets +4 additional enemies - a wide-area storm.", 2, 3, "sky_storm_variant", "bonus_targets", "4.0"),
    ("U_SKY_MeteorShafts.tres", "uid://bowu_sky4_meteorshafts", "sky_t3_meteor_shafts", "Meteor Shafts",
     "Skyfall deals +60% damage.", 2, 3, "sky_storm_variant", "bonus_damage_mult", "0.6"),
    ("U_SKY_DoubleFall.tres", "uid://bowu_sky5_doublefall", "sky_t3_double_fall", "Double Fall",
     "Skyfall strikes each enemy twice.", 2, 3, "sky_storm_variant", "bonus_hits", "1.0"),

    # Hailstorm (hail) - rapid multi-hit single target
    ("U_HAIL_RapidLoose.tres", "uid://bowu_hail1_rapidloose", "hail_t1_rapid_loose", "Rapid Loose",
     "Hailstorm fires +1 additional arrow.", 1, 1, "", "bonus_hits", "1.0"),
    ("U_HAIL_Splinter.tres", "uid://bowu_hail2_splinter", "hail_t2_splinter", "Splinter",
     "Hailstorm strikes +1 additional enemy.", 1, 2, "", "bonus_targets", "1.0"),
    ("U_HAIL_Flurry.tres", "uid://bowu_hail3_flurry", "hail_t3_flurry", "Flurry",
     "Hailstorm fires +3 additional arrows - a relentless barrage.", 2, 3, "hail_storm_variant", "bonus_hits", "3.0"),
    ("U_HAIL_Bloodletting.tres", "uid://bowu_hail4_bloodletting", "hail_t3_bloodletting", "Bloodletting",
     "Hailstorm deals +40% damage.", 2, 3, "hail_storm_variant", "bonus_damage_mult", "0.4"),
    ("U_HAIL_SuppressingFire.tres", "uid://bowu_hail5_suppressingfire", "hail_t3_suppressing_fire", "Suppressing Fire",
     "Hailstorm sprays +2 additional enemies.", 2, 3, "hail_storm_variant", "bonus_targets", "2.0"),

    # Steady Aim (sa) - self-buff
    ("U_SA_LongDraw.tres", "uid://bowu_sa1_longdraw", "sa_t1_long_draw", "Long Draw",
     "Steady Aim lasts 10 seconds longer.", 1, 1, "", "buff_duration_bonus", "10.0"),
    ("U_SA_Conserve.tres", "uid://bowu_sa2_conserve", "sa_t2_conserve", "Conserve",
     "Reduces Steady Aim's mana cost by 4.", 1, 2, "", "mana_flat_reduction", "4.0"),
    ("U_SA_Deadeye.tres", "uid://bowu_sa3_deadeye", "sa_t3_deadeye", "Deadeye",
     "Steady Aim's cooldown is reduced by 8 seconds.", 2, 3, "sa_stance_variant", "cooldown_flat_reduction", "8.0"),
    ("U_SA_PerfectStance.tres", "uid://bowu_sa4_perfectstance", "sa_t3_perfect_stance", "Perfect Stance",
     "Steady Aim lasts 25 seconds longer.", 2, 3, "sa_stance_variant", "buff_duration_bonus", "25.0"),
    ("U_SA_Zen.tres", "uid://bowu_sa5_zen", "sa_t3_zen", "Zen",
     "Reduces Steady Aim's mana cost by 10.", 2, 3, "sa_stance_variant", "mana_flat_reduction", "10.0"),

    # Eagle Eye (ee) - party crit buff
    ("U_EE_Farsight.tres", "uid://bowu_ee1_farsight", "ee_t1_farsight", "Farsight",
     "Eagle Eye lasts 20 seconds longer.", 1, 1, "", "buff_duration_bonus", "20.0"),
    ("U_EE_Clarity.tres", "uid://bowu_ee2_clarity", "ee_t2_clarity", "Clarity",
     "Reduces Eagle Eye's mana cost by 4.", 1, 2, "", "mana_flat_reduction", "4.0"),
    ("U_EE_HawksEye.tres", "uid://bowu_ee3_hawkseye", "ee_t3_hawks_eye", "Hawk's Eye",
     "Eagle Eye's cooldown is reduced by 12 seconds.", 2, 3, "ee_vision_variant", "cooldown_flat_reduction", "12.0"),
    ("U_EE_EternalVigil.tres", "uid://bowu_ee4_eternalvigil", "ee_t3_eternal_vigil", "Eternal Vigil",
     "Eagle Eye lasts 60 seconds longer.", 2, 3, "ee_vision_variant", "buff_duration_bonus", "60.0"),
    ("U_EE_FocusFire.tres", "uid://bowu_ee5_focusfire", "ee_t3_focus_fire", "Focus Fire",
     "Reduces Eagle Eye's mana cost by 8.", 2, 3, "ee_vision_variant", "mana_flat_reduction", "8.0"),

    # Disengage (dis) - kite dash + shot
    ("U_DIS_LightFeet.tres", "uid://bowu_dis1_lightfeet", "dis_t1_light_feet", "Light Feet",
     "Reduces Disengage's cooldown by 1 second.", 1, 1, "", "cooldown_flat_reduction", "1.0"),
    ("U_DIS_PartingShot.tres", "uid://bowu_dis2_partingshot", "dis_t2_parting_shot", "Parting Shot",
     "Disengage's arrow deals +30% damage.", 1, 2, "", "bonus_damage_mult", "0.3"),
    ("U_DIS_SmokeBomb.tres", "uid://bowu_dis3_smokebomb", "dis_t3_smoke_bomb", "Smoke Bomb",
     "Disengage deals +70% damage as you vanish.", 2, 3, "dis_escape_variant", "bonus_damage_mult", "0.7"),
    ("U_DIS_Caltrops.tres", "uid://bowu_dis4_caltrops", "dis_t3_caltrops", "Caltrops",
     "Disengage's parting shot strikes +2 additional enemies in your path.", 2, 3, "dis_escape_variant", "bonus_targets", "2.0"),
    ("U_DIS_Evasion.tres", "uid://bowu_dis5_evasion", "dis_t3_evasion", "Evasion",
     "Disengage's cooldown is reduced by an additional 2 seconds - kite on demand.", 2, 3, "dis_escape_variant", "cooldown_flat_reduction", "2.0"),

    # Snipe (snp) - burst finisher
    ("U_SNP_SteadyHand.tres", "uid://bowu_snp1_steadyhand", "snp_t1_steady_hand", "Steady Hand",
     "Reduces Snipe's cooldown by 1 second.", 1, 1, "", "cooldown_flat_reduction", "1.0"),
    ("U_SNP_ArmorPierce.tres", "uid://bowu_snp2_armorpierce", "snp_t2_armor_pierce", "Armor Pierce",
     "Snipe deals +30% damage.", 1, 2, "", "bonus_damage_mult", "0.3"),
    ("U_SNP_Killshot.tres", "uid://bowu_snp3_killshot", "snp_t3_killshot", "Killshot",
     "Snipe deals +90% damage - a true execution shot.", 2, 3, "snp_shot_variant", "bonus_damage_mult", "0.9"),
    ("U_SNP_PinningShot.tres", "uid://bowu_snp4_pinningshot", "snp_t3_pinning_shot", "Pinning Shot",
     "Snipe's arrow punches through +1 additional enemy behind the target.", 2, 3, "snp_shot_variant", "bonus_targets", "1.0"),
    ("U_SNP_DoubleTap.tres", "uid://bowu_snp5_doubletap", "snp_t3_double_tap", "Double Tap",
     "Snipe fires a second arrow at the target.", 2, 3, "snp_shot_variant", "bonus_hits", "1.0"),

    # Fleet Fingers (ff) - +DEX% passive (1/2/2 = +5%)
    ("U_FF_Nimble.tres", "uid://bowu_ff1_nimble", "ff_t1_nimble", "Nimble",
     "Increases Fleet Fingers' DEX bonus by +1%.", 1, 1, "", "passive_stat_percent_bonus", "1.0"),
    ("U_FF_Quick.tres", "uid://bowu_ff2_quick", "ff_t2_quick", "Quick",
     "Increases Fleet Fingers' DEX bonus by +2%.", 1, 2, "", "passive_stat_percent_bonus", "2.0"),
    ("U_FF_LightningReflexes.tres", "uid://bowu_ff3_lightningreflexes", "ff_t3_lightning_reflexes", "Lightning Reflexes",
     "Increases Fleet Fingers' DEX bonus by +2%.", 2, 3, "", "passive_stat_percent_bonus", "2.0"),

    # Keen Eye (ke) - +CRITCHANCE passive
    ("U_KE_Focused.tres", "uid://bowu_ke1_focused", "ke_t1_focused", "Focused",
     "Increases Keen Eye's critical hit chance bonus.", 1, 1, "", "passive_stat_percent_bonus", "1.0"),
    ("U_KE_Precise.tres", "uid://bowu_ke2_precise", "ke_t2_precise", "Precise",
     "Increases Keen Eye's critical hit chance bonus.", 1, 2, "", "passive_stat_percent_bonus", "2.0"),
    ("U_KE_Unerring.tres", "uid://bowu_ke3_unerring", "ke_t3_unerring", "Unerring",
     "Increases Keen Eye's critical hit chance bonus.", 2, 3, "", "passive_stat_percent_bonus", "2.0"),

    # Survival Instinct (si) - +Max HP% passive (1/2/2 = +5%)
    ("U_SI_Hardy.tres", "uid://bowu_si1_hardy", "si_t1_hardy", "Hardy",
     "Increases Survival Instinct's Max HP bonus by +1%.", 1, 1, "", "passive_stat_percent_bonus", "1.0"),
    ("U_SI_Rugged.tres", "uid://bowu_si2_rugged", "si_t2_rugged", "Rugged",
     "Increases Survival Instinct's Max HP bonus by +2%.", 1, 2, "", "passive_stat_percent_bonus", "2.0"),
    ("U_SI_Indomitable.tres", "uid://bowu_si3_indomitable", "si_t3_indomitable", "Indomitable",
     "Increases Survival Instinct's Max HP bonus by +2%.", 2, 3, "", "passive_stat_percent_bonus", "2.0"),
]


def main():
    os.makedirs(BASE, exist_ok=True)
    count = 0
    for (fname, uid, uid_id, name, desc, cost, tier, vgroup, ekey, mag) in UPGRADES:
        content = TEMPLATE.format(
            uid=uid, script_uid=SCRIPT_UID, upgrade_id=uid_id, upgrade_name=name,
            description=desc, point_cost=cost, tier=tier, variant_group=vgroup,
            effect_key=ekey, magnitude=mag)
        path = os.path.join(BASE, fname)
        with open(path, "w", encoding="utf-8", newline="\n") as f:
            f.write(content)
        count += 1
    print("Wrote %d upgrade files to %s" % (count, BASE))


if __name__ == "__main__":
    main()
