#   kysul        legacy mutation name, now src/Item.cpp Item::Damage: 2000
#                acid trials per bow, missile and sword; energy items are
#                unharmed, while all plain controls take damage (inc-pu6v.179)
@@@ next hunk
#   energy-acid          2000 acid trials per type, plain and energy controls
@@@ next hunk
for it in "short bow" "crossbow bolt" "long sword"; do
    _need energy-acid "$it" trials 2000 "setup: fewer than 2000 acid trials for a $it"
    _need energy-acid "$it" harmed 0 "an energy $it takes acid damage"
    _need energy-acid "$it" plain_unhurt 0 "control: a plain $it takes no acid damage"
done
