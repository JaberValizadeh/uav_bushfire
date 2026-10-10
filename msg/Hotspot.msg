# uav_bushfire/Hotspot
#
# One fire on the ground, and the deal on offer for putting it out.
#
# There is no z on the *fire*, and its absence is the scenario. The floating-
# treasure version of this package carried an altitude because the target could
# be anywhere in the volume, so being underneath it was not the same as reaching
# it. A fire is on the ground: two numbers place it again, and the third
# dimension moves off the target and onto the *approach* - the aircraft has to
# get down to the fire to do anything about it, which is what suppress_altitude
# is for. (station_z below is not the fire's altitude; it is the height this
# drone holds at while bombing, staggered so a crew does not stack up.)
#
# intensity is one number doing two jobs, and that is the point of the
# scenario. It is what the fire is *worth* and it is how much work it takes:
# a 10 pays five times a 2 and takes five times as long to put out. That is
# what makes joining somebody else's fire a real decision - the payout is
# split, but so is the labour, and the second effect is the one that grows
# with crew size.
#
# suppressed=false : this fire is burning; it is this drone's assignment.
# suppressed=true  : the crew just finished it, and `reward` is this drone's
#                    equal share of `intensity`.

uint32  id          # which fire slot this is; stable for the life of the run
float64 x           # ground position in the world frame (metres)
float64 y
float64 intensity   # the value of this fire, and its size (1 - 10)

# Suppression is work, not an instant. work_total is drone-seconds of
# on-station bombing needed; every crew member overhead adds one second of
# work per second, so n drones finish in 1/n of the time one would take.
float64 work_total
float64 work_done

uint32  crew        # drones committed to this fire right now
float64 share       # intensity / crew - what each member gets when it is out

# Where the receiving drone should hold while bombing. Equal to (x, y) for a
# lone drone; a slot on a ring around the fire, at its own altitude, when there
# is a crew - two aircraft station-keeping on the same point is a collision.
# In HotspotArray these carry no meaning and repeat (x, y).
float64 station_x
float64 station_y
float64 station_z

bool    suppressed  # true only in the message that closes the job
float64 reward      # paid to THIS drone; meaningful only when suppressed
