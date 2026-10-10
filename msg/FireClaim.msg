# uav_bushfire/FireClaim
#
# A drone announcing which fire it is joining. Published on /bushfire/claims by
# every aircraft; fire_spotter is the registry that accepts or ignores it.
#
# The choice lives in the drone and the bookkeeping lives in the spotter, and
# the split is deliberate. Every aircraft can see the whole fire ground on
# /bushfire/hotspots - position, value, work left, and how many drones are
# already on each fire - so it has everything it needs to decide what is worth
# flying to. What it cannot do alone is agree with two other drones about who
# is on what, at 10 Hz, without a race. So the decision is local and the
# ledger is central.
#
# The spotter ignores a claim from a drone that is already committed to
# something else. That is the commitment rule: a crew that could be walked out
# on halfway through would never be worth joining, since the value of joining
# is entirely in the labour being shared.

string  drone    # namespace of the claiming aircraft, e.g. uav_0
uint32  fire_id  # the fire it wants to join
bool    release  # true = giving up a fire it holds, rather than joining one
