# uav_bushfire/HotspotArray
#
# Every fire currently on the ground, published by fire_spotter.
#
# This is the message the single-treasure design did not need. With one target
# per drone the state of the world was one message on one namespaced topic;
# with a shared fire ground there is a set of them, every drone is affected by
# fires it was not assigned, and a monitor or an RViz view wants all of it at
# once rather than three private slices.
#
# It is also the market board. Each entry carries its fire's value, the work
# left in it and the crew already on it, which is exactly what an idle drone
# needs to work out what its own share would be worth and how long it would
# take to earn - see FireClaim.msg. The station_* fields are the one part that
# means nothing here: a station is per drone, so they repeat (x, y).
#
# Suppressed fires are not listed. A slot that has just been put out reappears
# here at its new position once it re-ignites elsewhere, under the same id.

std_msgs/Header header
Hotspot[]        hotspots
