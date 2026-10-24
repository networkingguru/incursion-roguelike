#!/bin/bash
# gate: live
# inc-w91w: found-trap attacks, remote area victims, and unchanged Rogue disarm.
# fact: class, stats, kit -- orc-barbarian/rogue-seed1-opt0822.sav fixtures
# fact: options -- tools/fixtures/options-2026-08-22.dat
# fact: map, no AI, found trap and its distance -- INCURSION_TRAP_ATTACK_PROBE scene
# fact: hit/miss/fumble d20 and confirmation -- INCURSION_LOF_FORCE_ROLL
# fact: avoidance/effect save -- INCURSION_FORCE_SAVE_ROLL
# fact: disarm skill roll -- INCURSION_RUNTO_SKILL_ROLL=20
# fact: armed flag, blindness, faerie-fire status, HP, time, XP -- probe before/after state
# fact: ADJUST_PAIN status (present/absent), never its magnitude or duration -- probe after-state; sval NOSAVE so the save roll cannot gate it
# fact: faerie-fire duration is positive or absent, not its random value -- normal spell duration bounds
# fact: attack target -- normal Attack menu cursor, staged trap one square east
# fact: shooter kit -- probe wields a short bow and 20 flight arrows (shot-thrown: a dagger)
# fact: shot target square and its lighting -- probe lights the room; keys aim three squares east
# fact: staged creature (shot-under, shot-between) never acts -- probe gives it permanent ASLEEP
# fact: staged creature hit points -- probe sets 10000, so a strike shows as a drop
# fact: strike on the creature in between -- INCURSION_LOF_FORCE_ROLL=20 (natural 20 always hits)
. "$(dirname "$0")/check_lib.sh"
CHECK_OPTIONS=tools/fixtures/options-2026-08-22.dat
export INCURSION_RUNTO_SKILL_ROLL=20
MODES="hit miss fumble avoid area-inside area-outside area-script rogue"
MODES="$MODES shot-hit shot-miss shot-fumble shot-thrown shot-under shot-between"
for mode in $MODES; do
    export INCURSION_TRAP_ATTACK_PROBE="$mode" INCURSION_LOF_FORCE_ROLL=20 INCURSION_FORCE_SAVE_ROLL=1
    export INCURSION_LOAD=tools/fixtures/chars/orc-barbarian-seed1-opt0822.sav
    keys=tools/keys/trap-attack.keys
    case "$mode" in
        miss) export INCURSION_LOF_FORCE_ROLL=2 ;;
        fumble) export INCURSION_LOF_FORCE_ROLL=1 ;;
        avoid) export INCURSION_LOF_FORCE_ROLL=1 INCURSION_FORCE_SAVE_ROLL=20 ;;
        area-*) keys=tools/keys/trap-attack-core.keys ;;
        shot-miss) export INCURSION_LOF_FORCE_ROLL=2; keys=tools/keys/trap-shot-loc.keys ;;
        shot-fumble) export INCURSION_LOF_FORCE_ROLL=1; keys=tools/keys/trap-shot-loc.keys ;;
        shot-hit|shot-between) keys=tools/keys/trap-shot-loc.keys ;;
        shot-thrown) keys=tools/keys/trap-shot-throw.keys ;;
        shot-under) keys=tools/keys/trap-shot-pick.keys ;;
        rogue) export INCURSION_LOAD=tools/fixtures/chars/orc-rogue-seed1-opt0822.sav
               keys=tools/keys/trap-attack-rogue.keys ;;
    esac
    check_run "$keys" "${TRAP_CHECK_SEED:-1}"
    python3 - "$CHECK_RUN/logs/errors.log" "$mode" <<'PY'
import re,sys
text=open(sys.argv[1]).read(); mode=sys.argv[2]
lines=[l for l in text.splitlines() if 'TRAP_ATTACK' in l]
print('\n'.join(lines))
stage=next((l for l in lines if ' stage ' in l), '')
assert stage and 'armed=1' in stage and 'blind=0' in stage and 'lit=0' in stage, 'missing clean armed baseline'
assert ('class=rogue' if mode=='rogue' else 'class=barbarian') in stage.lower(), 'wrong fixture class'
if mode.startswith('shot-'):
    kv=lambda l:{k:int(v) for k,v in re.findall(r'(\w+)=(-?\d+)',l)}
    shots=[l for l in lines if 'TRAP_ATTACK shot ' in l]
    assert len(shots)==1, 'expected exactly one shot, saw %d'%len(shots)
    sh=kv(shots[0])
    equip=next((l for l in lines if 'TRAP_ATTACK equip' in l),'')
    assert 'hand=1' in equip and 'ammo=1' in equip, 'shooter not equipped'
    assert ('weapon=dagger' in equip)==(mode=='shot-thrown'), 'wrong shooter weapon'
    detail=next((l for l in lines if f'TRAP_ATTACK mode={mode} ' in l),'')
    d=kv(detail) if detail else {}
    assert sh['time']>0, 'the shot took no time'
    if mode=='shot-between':
        # the creature in between is struck; the shot never reaches the trap
        assert sh['trap_attacked']==0 and not detail, 'trap was attacked through a creature'
        assert sh['armed']==1, 'trap disarmed through a creature'
        assert sh['mon_hp_after']<sh['mon_hp_before'], 'creature in between was not struck'
        assert sh['blind']==0 and sh['hp_before']==sh['hp_after'], 'shooter touched'
    else:
        assert sh['trap_attacked']==1 and d, 'shot did not resolve against the trap'
        want_hit=mode in ('shot-hit','shot-thrown','shot-under')
        assert d['hit']==int(want_hit), 'wrong hit'
        assert d['fumble']==int(mode=='shot-fumble'), 'wrong fumble'
        assert sh['armed']==int(mode=='shot-miss'), 'wrong armed state'
        assert sh['blind']==int(mode=='shot-fumble'), 'found-trap save effect on wrong creature'
        assert sh['hp_before']==sh['hp_after'], 'shooter damaged'
        if mode=='shot-under':
            assert sh['mon']==1 and sh['mon_blind']==1, 'creature on the trap not blinded'
            assert sh['mon_hp_after']==sh['mon_hp_before'], 'missile struck the creature on the trap'
        else:
            assert sh['mon']==0, 'unexpected creature'
elif mode=='rogue':
    assert any('TRAP_ATTACK rogue armed=0' in l for l in lines), 'Rogue did not disarm'
else:
    result=next((l for l in lines if f'TRAP_ATTACK mode={mode} ' in l),'')
    d={k:int(v) for k,v in re.findall(r'(\w+)=(-?\d+)',result)}
    assert d, 'attack did not execute'
    assert d['time']>0 and d['xp_before']==d['xp_after'], 'time/XP invariant'
    assert d['hp_before']==d['hp_after'], 'unexpected damage'
    assert d['armed']==int(mode in ('miss','avoid')), 'wrong armed state'
    assert d['fumble']==int(mode in ('fumble','avoid')), 'wrong fumble'
    assert d['hit']==int(mode in ('hit','area-inside','area-outside','area-script')), 'wrong hit'
    assert d['blind']==int(mode=='fumble'), 'wrong found-trap save/effect'
    assert d['lit']==int(mode=='area-inside'), 'area reached wrong square'
    if mode=='area-inside': assert d['duration']>0, 'victim-only duration leaked onto attacker'
    if mode=='area-script':
        assert d['armed']==0, 'trap not disarmed after the hit'
        assert d['pain']==1, 'area victim-only script did not reach the attacker'
print('PASS:',mode)
PY
    if [ "$?" -ne 0 ]; then CHECK_FAIL=1; else CHECK_EXPECTS=$((CHECK_EXPECTS+1)); fi
done
check_done "found-trap attack state transitions and Rogue disarm"
