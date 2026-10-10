# uav_bushfire

Three **hector quadrotors** water-bomb ground fires in a Gazebo stand of
timber, on ROS Noetic.

Fires burn on the ground, each worth what it is big. **Every drone chooses its
own fire**, several can work the same one, and the fire's value is **split
equally between whoever chose it** — but so is the labour, so a big fire is
worth crewing and a small one is not. Having chosen, a drone is committed until
the job is done.

Each aircraft takes off, picks a fire off the board, transits at cruise
altitude while dodging tree trunks with a mast-mounted laser, arrives at its
station over the fire, **descends onto it** and bombs until the fire is out,
then climbs away and chooses again. Flying over a fire does not put it out —
you have to get down to it, and stay. One command:

```bash
source ~/uav_ws/src/uav_pick_place/setup_uav.bash
roslaunch uav_bushfire bushfire.launch
```

Add `gui:=false` to run it headless, which is how it was tested, and
`rviz:=true` to watch the whole incident in one view.

To run RViz separately against an incident already in progress:

```bash
roslaunch uav_bushfire bushfire_rviz.launch
```

### Or one stage at a time

`bushfire.launch` is nothing but these three run together, and takes the same
arguments. Run them in separate terminals when working on one piece — the world
is the slowest part to load and the part you least often want to restart:

| | terminal | |
|---|---|---|
| 1 | `roslaunch uav_bushfire bushfire_world.launch` | Gazebo + the stand. Leave it up. |
| 2 | `roslaunch uav_bushfire bushfire_fleet.launch` | three aircraft + the fire spotter |
| 3 | `roslaunch uav_bushfire bushfire_rviz.launch` | the view |

Step 1 brings up the roscore, so it has to be first. **Step 3 only subscribes** —
start, kill and restart it at any point in a run without disturbing Gazebo or
the fleet, which is the reason to have it as its own file.

Step 2 is the one to iterate on, and a parameter sweep costs one relaunch
instead of reloading the world:

```bash
roslaunch uav_bushfire bushfire_fleet.launch max_crew:=2
```

The aircraft are spawned by step 2, so relaunching it into a world that still
holds them fails the spawn with `entity already exists` — the models belong to
Gazebo and outlive the launch that asked for them. Delete them first, or restart
step 1.

---

## Requirements and install

Ubuntu 20.04, **ROS Noetic** and Gazebo 11. hector_quadrotor and the packages around it are not released as Noetic debs, so the workspace is a source build:

```bash
mkdir -p ~/uav_ws/src && cd ~/uav_ws/src
git clone https://github.com/ros-geographic-info/unique_identifier.git
git clone https://github.com/ros-geographic-info/geographic_info.git
git clone https://github.com/RAFALAMAO/hector-quadrotor-noetic.git
git clone https://github.com/JaberValizadeh/uav_bushfire.git

cd ~/uav_ws
rosdep install --from-paths src --ignore-src -r -y
catkin_make --pkg uuid_msgs unique_id geographic_msgs geodesy
catkin_make
```

The two-stage build is not optional. `hector_pose_estimation_core` includes `geographic_msgs` headers without declaring a dependency on the target that generates them, so a single parallel build races and fails on the first pass.

### Environment

The commands in this README source `~/uav_ws/src/uav_pick_place/setup_uav.bash` from the author's workspace. That package is not published; if you do not have it, this is the equivalent, in every terminal:

```bash
source /opt/ros/noetic/setup.bash
source ~/uav_ws/devel/setup.bash

# hector's Gazebo plugins
export GAZEBO_PLUGIN_PATH=$HOME/uav_ws/devel/lib:${GAZEBO_PLUGIN_PATH:-}
# the quadrotor meshes, for package:// URIs in the URDF
export GAZEBO_MODEL_PATH=$HOME/uav_ws/src/hector-quadrotor-noetic:${GAZEBO_MODEL_PATH:-}
```

---

## The scenario, and what it inverts

This package began as a treasure hunt: three drones chasing gold orbs that
floated at random altitudes. That version is worth describing, because the fire
scenario is its inverse in almost every respect and most of the interesting
design follows from the flip.

|  | floating treasure | ground fire |
|---|---|---|
| where the target is | anywhere in the volume | on the ground, z = 0 |
| what the message carries | x, y, **z**, value | x, y, intensity — **no z** |
| altitude's role | part of the *target*, matched on approach | a *limit* on the approach |
| arrival test | 3D distance | horizontal radius **and** an altitude band |
| who owns a target | one private spawner per drone | one spotter owns them all |
| how a drone gets one | it always had one | it **chooses** one and claims it |
| how many drones per target | exactly one | as many as think it is worth it |
| what a target pays | its value, to whoever gets there | its value, **split equally** between the drones that chose it |
| collecting it | instantaneous, on arrival | **drone-seconds of work**, shared by the crew |
| changing your mind | free | not allowed until the job is done |
| end of the chase | fly to the point | arrive overhead, then descend onto it |

**The target loses a dimension and the approach gains one.** A floating
treasure was reached by flying to a point, so altitude was just another axis of
the same problem, and being underneath the target was not the same as reaching
it. A fire cannot be flown to at all — the aircraft would have to land on it.
So arrival and suppression come apart: `CHASE` ends *overhead* at cruise
altitude, and then the drone has to get down onto something it is now directly
above.

**Fires are shared, and sharing one is the point.** The treasure version gave
every drone a private spawner owning a private target, and no node ever had to
know the other drones existed. Fires burn where they burn, any aircraft can
take any of them, and more than one aircraft can take the same one — so
`fire_spotter` holds the whole picture: what each fire is worth, how much of it
is left, who is on it and what they are each owed.

## How it works

```
                    ┌── /bushfire/hotspots ────────> pose_fire_monitor  (logs)
fire_spotter ───────┼── /bushfire/markers ─────────> RViz
 (owns every fire,  │
  keeps the ledger) └── /uav_N/bushfire/target ────> fire_suppressor ──/cmd_vel──> controller/twist
       ▲    ▲                                             ▲        ▲
       │    └───────── /bushfire/claims ──────────────────┘        │
       └──────── /uav_N/ground_truth/state ────────────────┘      scan
```

| Node | Scope | Role |
|---|---|---|
| `fire_spotter` | **global** | Owns a fixed pool of fires, spawns their Gazebo models and RViz markers, accepts claims, meters the bombing, splits the value, re-ignites a suppressed slot elsewhere |
| `fire_suppressor` | per drone | **Chooses** a fire and claims it; `TAKEOFF` → `ALIGN` → `CHASE` → `DESCEND` → `CLIMB` → `WAIT`; laser avoidance, geofence, respawn, scoreboard |
| `pose_fire_monitor` | per drone | Passive. Logs pose, the job, the crew and the share |

### What a fire is worth, and what it costs

Intensity (1–10) is one number doing two jobs, and the pairing is the whole
mechanic:

* **value** — the fire pays `intensity`, **split equally between every drone
  that chose it**. Three drones on a 9 get 3 each.
* **size** — it takes `intensity × work_per_intensity` **drone-seconds** of
  on-station bombing. Every crew member overhead contributes a second of work
  per second, so a crew of *n* finishes in *1/n* of the time.

Neither half works alone. Split-only payout makes joining somebody else's fire
strictly worse than taking your own, so no crew ever forms. Work-only makes
crews free, so everybody piles onto one fire. Together there is a real question
with a real answer.

### Choosing a fire

Nobody is assigned anything. `fire_spotter` publishes the whole board —
position, value, work remaining, crew — and each drone picks for itself, on
**share per second**:

```
n       = crew + 1                    (me, joining)
share   = intensity / n               paid equally to everyone who chose it
eta     = travel + work_left / n      n drones do n seconds of work per second
utility = share / eta
```

Both appearances of `n` matter and they pull opposite ways: joining halves the
payout *and* halves the time. On a small fire that trade is bad and the drone
goes alone; on a big one it is the best thing on the board for everybody, so
**bigger fires end up with bigger crews** — not because anything says so, but
because that is where the arithmetic comes out. Over a 90-second run:

| fire value | ≤ 4 | ≥ 7 |
|---|---|---|
| average crew | 1.17 | 1.88 |

Distance enters as travel time in the denominator rather than as a rule, so a
near fire wins ties and a far one has to be worth the flight.

**A claim is binding.** While a drone holds a fire, its claims on anything else
are ignored; it is released when the job is done. This is the reverse of the
old nearest-first tasking, which recomputed everything every tick, and crews
are the reason: an `eta` computed from a crew of three is a lie if two of them
can leave, so a coalition you can walk out of is not worth joining, so no
coalition forms. Two escapes exist, both faults rather than choices — a drone
that has not been on station for `~commit_timeout` is dropped, and a drone that
gets **rescued** releases its own fire on the way past, because its crewmates
should not be diluted by an aircraft that has just been teleported home.

### Where a crew stands

Not on the fire — two drones station-keeping on the same point is a collision,
and with crews that is the normal case rather than bad luck. A crew of *n* is
spread over a ring, `r = crew_separation / (2 sin(π/n))`, and stacked in
altitude a step apart:

```
crew of 1   on the fire,          0.95 m
crew of 2   r = 0.50 m,      0.95 / 1.10 m
crew of 3   r = 0.58 m,  0.95 / 1.10 / 1.25 m
```

The spotter owns that geometry, because it is the only node that knows how many
drones are on a fire and in what order they joined, and it sends each drone its
own station with every tasking. Both the ring and the stack have to stay inside
the suppression test, which is why `collect_dist` (1.00 m) and
`suppress_altitude` (1.45 m) are wider here than one drone would ever need.

### The suppression test

```
dist_xy <= collect_dist   AND   min_drop_altitude <= z <= suppress_altitude
     (1.00 m)                        (0.45 m)              (1.45 m)
```

Measured to the **fire**, not to the drone's ring station: a crew member
holding a sloppy station is still over the fire and still working, and making
the test the station would let collision-avoidance geometry silently stop the
work.

The ceiling is the point of the scenario: a drone cruising over a fire has not
put it out. The floor is there because "under the ceiling" is also true of an
aircraft **sitting on the ground** — see the sixth bug below.

Passing the test no longer *ends* the fire. It means this drone is bombing, and
the fire's work counter advances while it is; the fire ends when the counter
fills. A 10 takes twelve drone-seconds — twelve seconds alone, four with a full
crew.

### Why `DESCEND` cannot fly like `CHASE`

`CHASE` commands body-forward velocity only, and yaws to steer. That is what
makes the laser meaningful: the scanner is bolted to the airframe, so its
"front" sector only means "where I am going" if the drone is pointed where it
is going.

That is useless for the descent, where the error is 20 cm on an arbitrary
bearing and the drone is not yawing any more. `DESCEND` rotates the world-frame
position error into the body frame and commands **both** `linear.x` and
`linear.y` — proper station-keeping. It is the only phase that uses lateral
velocity, and it is safe there precisely because the aircraft is stopped over a
fire the spotter placed clear of the trees. Translating sideways is exactly
what makes the laser sectors meaningless, which is why `CHASE` never does it.

It also has to be a position controller rather than an arrival test, because
the station **moves**: a drone arriving on or leaving a fire changes the ring
for everybody on it, and the error simply steps. And `DESCEND` is now where
most of the run is spent — a lone drone on a 10 holds it for twelve seconds,
which is exactly the cost the market arithmetic weighs a smaller share against.

`CLIMB` is not decoration either: leaving at drop height means crossing the
fire ground at 0.95 m, under the altitude the geofence and avoidance were tuned
for, and into whatever the next fire is sitting next to.

## The scene

A **12 × 12 m** fire ground: fifteen eucalypts scattered across it, ringed by a
bulldozed firebreak, with standing bush beyond. Three launch points on the y
axis, kept clear.

**Fires are lit anywhere inside it.** That is `world_half_size`, and it was
4.0 m — an 8 × 8 m square with the eight trees standing in a ring *around* the
outside of it, so every fire, every transit and every bombing run happened in
one small box. Four times the area now, and the trees are spread through the
whole of it rather than fencing it.

`worlds/bushfire.world` is **generated**, by `scripts/make_bushfire_world`,
together with the tiling textures it is painted with:

```bash
rosrun uav_bushfire make_bushfire_textures    # the textures, first
rosrun uav_bushfire make_bushfire_world
```

**`config/obstacles.yaml` is generated by the same pass**, and that is the
point of it. The trunk list used to be eight `[x, y, 0.35]` entries written by
hand in *two* launch files, with a comment in each saying to keep them in step
with the world and nothing checking that you had. Thirty-three trunks cannot be
maintained that way. Now the loop that places a tree writes its entry, the
launches load the file, and there is only one copy to be wrong.

Everything else scales off `FIRE_HALF` in the generator — the geofence that has
to enclose the ground, the break that rings it, the bush that has to stay
outside the geofence, and how many trees fill it at a flyable density. It
prints the launch arguments that match what it wrote:

```
  fire ground : 12 x 12 m, fires anywhere inside +-6.0 m
  geofence    : soft 6.8, hard 10.0  (set these in one_uav.launch)
  launch args : world_half_size:=6.0 fence_half_size:=6.8 fence_hard_size:=10.0
```

`FIRE_HALF` in the generator is the one number to change to resize the ground.

One trap worth knowing: `bushfire.launch` includes the fleet with
`pass_all_args="true"`, so **its** copies of `world_half_size` and
`num_hotspots` shadow the fleet launch's. Changing them in
`bushfire_fleet.launch` alone changes nothing when you start from
`bushfire.launch`, which is how it is normally started. Both, or neither.

Trunks are 3 m tall with collision. **Nothing else on the fire ground has
collision at all** — canopies, branches, roots, logs, stumps, rocks and grass
tussocks are visual only, and that is deliberate rather than lazy. The laser is
a horizontal plane on a mast: it sees trunks perfectly and cannot see anything
above or below the aircraft. A solid canopy would be an obstacle the drone can
hit and has no sensor able to detect — the exact scene the controller's own
header warns it cannot handle. Tops that a rotor passes through keep the
picture honest: **the aircraft only ever collides with things it could have
seen coming.**

Trunk height exists to stop the obvious cheat. An aircraft's answer to an
obstacle is to go over it, and if it can, the reactive avoidance this package
is built around never runs. The trunks are 3 m against a top cruise lane of
2.60, so the aircraft live *inside* the timber and have to go round things.

### There is no wall

There used to be one: four 3 m walls at ±6, boxing the whole thing in. They are
gone, and the reasons are worth separating, because one of them is about how it
looked and the other is about whether it worked.

It looked like a room. A 12 m box with trees in it, from every angle, and no
amount of texture on the trees fixes a scene whose dominant feature is four
walls.

And it was not doing the job it appeared to. Containment here is the
**geofence**, not the wall: past `fence_half_size` the drone turns round, and
past `fence_hard_size` it is teleported back to its launch point. Both scale
with the fire ground — **6.8 and 10.0** now, against fires lit out to 6.0.
The wall never had a chance to be the backstop — the suppressor's own header
records `uav_1` clipping one, going *over* it at 3.5 m, and still accelerating
275 m away with the motors running. A geofence cannot be flown over, and the
soft limit sits only 0.8 m outside the furthest a fire can be lit, so nothing
sends an aircraft past it in normal work.

What replaces it is what would really be there — the graded break at
**6.6–8.6 m**, which is the actual firebreak, and then unburnt bush past it.

The bush **starts outside the hard geofence** (10.8 m against 10.0), and that
is load-bearing rather than aesthetic. Its trunks collide — they are
laser-visible, so ghosts would be the dishonest option — but they are *not* in
the obstacle list, so `collision_monitor` does not score them. They therefore
have to sit where no aircraft can arrive. An earlier version put them inside
the band a soft-fenced drone actually reaches and a run flew `uav_1` straight
through them. `make_bushfire_world` now refuses to write them any closer, and
the check is a `SystemExit`, not a comment.

The trees in the **stand** are the instructive contrast: they run to 6.9 m,
slightly *past* the soft fence, and that is fine precisely because they *are*
in the obstacle list — laser-visible, avoided, and scored if struck.

**Measured, not assumed.** Five runs, all shut down cleanly so the collision
report prints. Runs 2–5 are the same textured world; 4 and 5 differ only in the
size of the fire ground:

| | 1. walled ±4 | 2. no walls ±4 | 3. + new flames | 4. ±12 m | 5. **±6 m** |
|---|---|---|---|---|---|
| fire ground | 8 × 8 m | 8 × 8 m | 8 × 8 m | 24 × 24 m | **12 × 12 m** |
| trees | 8, in a ring | 8 | 8 | 33 | **15** |
| flown | 888 s | 709 s | ~660 s | 625 s | 637 s |
| fires suppressed | 197 | 145 | 163 | 100 | 121 |
| **rate** | **0.222 /s** | 0.205 /s | **0.247 /s** | 0.160 /s | **0.190 /s** |
| drone–drone contacts | 7 | 8 | 5 | 1 | 2 |
| drone–tree contacts | 0 | 6 | 0 | 0 | **3** |
| rescues | 0 | 7 | 0 | 0 | 2 |
| crews of 2 / of 3 | — | — | — | 18% / 0% | **39% / 16%** |

**12 × 12 is the better ground of the two, and the crew figures are why.** At
24 × 24 the fires were far enough apart that drones almost always worked alone
— 18% of status samples showed a crew of two and *none* showed three, so the
coalition logic that the whole scenario is built around barely ran. At 12 × 12
it is 39% and 16%. Throughput is better too (0.190 against 0.160), because less
of each job is spent in transit.

The cost is honest and visible in the table: **three drone–tree contacts, where
the larger ground had none.** Fifteen trees in 144 m² is a denser stand than
thirty-three in 576 m², so the gaps the aircraft thread are tighter — 1.97 m of
clear air between two trunk surfaces against a 0.80 m rotor span. That is the
scenario doing its job rather than a regression; `avoid_dist` and `stop_dist`
are the knobs if you want it softer.

Note also what the first three runs' contact and rescue counts do across
otherwise-identical worlds (8 → 5 contacts, 7 → 0 rescues): those numbers are
dominated by where fires randomly cluster, not by the world. Run 2 alone looked
like a regression and was not.

### Making it look like a place

Every surface used to be a flat `<diffuse>` colour: eight brown cylinders with
one green ball each, four grey-brown boxes, and Gazebo's stock grey
chequerboard running to the horizon. `make_bushfire_textures` generates nine
tiling textures procedurally — cured grass, mineral earth, ash, two barks,
char, charred timber, granite — plus three eucalypt canopy variants.

The palette is specific and it is not the orchard next door. This is dry
eucalypt in fire weather: the grass is **cured**, not green, the leaf is olive
and blue-grey, and the ground is litter and bare earth rather than sward. A
green sward under a bushfire is the one thing that would make the scene read
wrong from any distance.

**One colour rule, checked as each texture is written: nothing may be both
warm-hued and strongly saturated.** The fires are the only saturated warm thing
in this world and they have to stay that way, or at a glance across the stand
you cannot tell which glow is a fire and which is dirt. Every texture reports
its worst warm-hued pixel against a floor of 150 and the script refuses to
write one that clears it.

This is a *look* constraint, not a correctness one, and the difference from
`uav_farm_survey` is worth being clear about: there the same check is
load-bearing, because `fruit_detector` is a colour detector and a red texture
becomes a false apple in every frame. Nothing here looks at a camera. Fail this
check and the scenario scores exactly the same — it just stops being legible.

Four things that were tried and did not work, kept because the failures are
more use than the fix:

| tried | what it looked like |
|---|---|
| firebreak as four stacked courses | three crisp lines the whole 12 m span — **decking** |
| the same courses cut into random-height segments | every box shows edges and a corner — **masonry** |
| eight trunk segments, for a finer taper | every segment restarts the texture — **stacked pipe** |
| one squashed sphere per grass tussock | a hard round silhouette on open ground — **eggs** |

The last one generalises: **no arrangement of axis-aligned boxes reads as
earth**, because what says earth is a continuous sloped surface, and a smooth
sphere stays a sphere however good the texture on it is. What breaks a sphere
is other spheres overlapping it, which is why a canopy is thirty small ones
rather than a dozen big ones, and what breaks a box is not being a box.

And one bug that cost two rounds of chasing the wrong thing: **Ogre's
`texture_unit` `scale` magnifies, it does not count repeats.** `scale 20` makes
the tile twenty times *bigger*, so the ground had one twentieth of a texture
stretched over a 60 m box and rendered as flat yellow through two separate
attempts at raising the texture's own contrast. The contrast was never the
problem. The scales in `make_bushfire_world` are now written as metres-per-tile
with that stated where they are defined.

### What a fire is made of

Gazebo Classic has no particle emitter and no cone primitive, so a flame is
spheres. `_flame_sdf()` in `scripts/fire_spotter` builds one out of **98 links**
at full intensity: six tongues of twelve beads, sixteen coals, seven smoke
puffs, a scorch disc and a point light.

| | |
|---|---|
| **many small beads** | a tongue is twelve shrinking spheres, not three big ones. Three big ones is what it was, and it read as a stack of balloons — a sphere large enough to take in whole stays a sphere however it is coloured. Same lesson as the canopies. |
| **a red ramp** | the gradient is most of what the eye uses to recognise a flame. It stays red through the bottom half and reaches yellow only near the top. |
| **a dim, wispy tip** | the ramp does *not* run to white. Emissive channels add on top of diffuse, so near-1.0 in all three saturates to white and the shape goes with it. Over the last third the emissive **falls** and the transparency climbs to 0.62 — that is what turns a bead into a wisp instead of a light bulb. |
| **wobble** | each bead is displaced from its own indices, scaled by `(0.25 + t)` so the flame is anchored at the base and wavers at the top. Without it every tongue is a smooth symmetric cone, which is a candle. |
| **a real light** | a point light at the base is the single biggest cue, because it is the only part that lights *anything else* — the ground, the trunks, the underside of a drone hovering over it. Emissive geometry illuminates nothing. |
| **a bed of coals** | sixteen lumps at four brightnesses from black char to bright coal, hotter toward the middle. It is the **range** that reads as embers. |
| **a drifting plume** | spheres of growing radius and falling opacity, leaning consistently, which reads as wind. |

Three failures worth keeping, all the same failure:

| tried | what it looked like |
|---|---|
| 3 large beads per tongue, ramp running to white | a stack of pale yellow **balloons** |
| a 0.09 m bright-orange cylinder for the ember bed | a glowing **plastic drum** with a hard circular edge |
| smoke as one translucent cylinder | a **glass tube** — two hard circular edges and a straight side, and smoke has none of those |

The smoke one also hid a real bug: transparency has to be set with
`<transparency>` on the `<visual>`, **not** as a fourth component of the
material colour. The alpha is the part that looks like it ought to work.

**The height ceiling is load-bearing.** The lowest crew member holds at about
`drop_altitude` (0.95 m), so a flame taller than that means an aircraft flies
through the top of the fire it is bombing. `_flame_top()` computes the real
figure from the shape constants and `_flame_sdf()` refuses to build anything
over 0.93 m — including the wobble's radius inflation, because a factor the
builder applies and the check does not is how a guard goes quietly stale. At
intensity 10 the flame reaches 0.871 m against a predicted bound of 0.875.

One honest limit: at about a metre away the beads are individually visible as
overlapping bubbles. Nothing in the scenario views a fire from there — the
aircraft bomb from 0.95 m directly above — but it is a real ceiling on what
sphere geometry can do without a particle system.

## Eight bugs worth knowing about

The flying is inherited from the treasure version, including everything learned
by debugging it — which was a lot, because that version scored **zero
collections in four minutes** before the first four of these were found. All
eight were found by running it, not by reading it: the last two came from the
first run of the coalition mechanic, and neither is visible in the code.

### 1. `/cmd_vel` is body-frame, not world-frame

hector's `TwistController` has two command inputs in different frames:

```cpp
void cmd_velCommandCallback(...)  { command_given_in_stabilized_frame_ = true;  }  // :139
void twistCommandCallback(...)    { command_given_in_stabilized_frame_ = false; }  // :127
```

`update()` rotates the command by the current yaw when that flag is set, so
`/cmd_vel` — the topic everything here publishes on — is **yaw-stabilized body
frame**: `linear.x` means *forward*. Building a world-frame command
`(speed·cos yaw, speed·sin yaw)` gets it rotated by yaw a second time and flies
the aircraft along **2 × yaw**. At a heading of 95° it travelled at 190° —
backwards, with its laser pointed at empty air.

Nothing about this is visible in a log: the drone flies, holds altitude, yaws
toward its target and reports a shrinking heading error the whole time. It just
never arrives.

### 2. The self-hit filter blinded it at contact range

Past ~32° of tilt the scan plane dips through the rotor discs and the drone
sees its own booms at ~0.40 m; read as obstacles, that means "boxed in" and the
aircraft stops for good. The guard was to discard everything closer than
0.55 m — which is exactly where trouble lives. Jammed against a trunk the laser
reads **0.33 m**; wedged in a corner, **0.24 m**. Both were discarded, so a
drone in contact with a wall saw a clear path *through* it and held full thrust
against it until it tipped over.

The rejection is now conditional on the thing that causes it: tilt is already
known from odometry, so below `~self_hit_tilt` returns are trusted to the
sensor floor, and only above it is anything inside `~self_hit_range` dropped.

### 3. Respawning without cutting the motors is a respawn loop

`auto_engage` is off — and in *this* scenario it could not be anything else,
since it cuts the motors on a commanded descent that is not being achieved,
which is landing detection, and `DESCEND` is a commanded descent onto the
ground held for as long as it takes. But `TwistController` only clears its PID
integrators in the branch it takes when the motors are **not** running, so
nothing ever resets them. Teleporting an upset drone home handed the levelled
aircraft the integral wound up fighting the tumble, and it spent it putting the
drone straight back over: **53 rescues in 90 seconds**, none of which flew. The
order has to be `/shutdown`, teleport, settle, `/engage`.

### 4. Re-aiming the instant you are past is a livelock

`CHASE` drops back to `ALIGN` on heading drift, and that was suppressed only
while the safety filter was *currently* triggered. But clearing the front
sector is the one thing a successful deflection guarantees: the drone turns off
the tree, the sector clears, the drift check fires on the same tick, `ALIGN`
yaws it straight back — and `ALIGN` does not translate, so there is no progress
to show for the deflection. One drone finished a run with two collections
against another's twelve. Deflections are now committed to for `~avoid_hold`.

### 5. Delete-then-spawn loses the model

Gazebo answers `spawn_sdf_model` and `delete_model` immediately but defers both
to a world update, so moving a target by deleting and respawning races itself:
the spawn reports success, the next delete arrives before the insertion has
happened, Gazebo says `model does not exist`, and the node believes there is no
model while the pending insertion goes ahead anyway. Measured: **33 failed
deletes in four and a half minutes, and two models where there should have been
three** — a drone flying hard at something the viewer could not see.

`set_model_state` replaces the pair: one atomic call against a model that
already exists, no window where the name is half-registered, and it works on a
`<static>` model. So the fires here are a **fixed pool spawned once and only
ever moved**, which is also why the Gazebo flame is a single size and intensity
is shown on the RViz marker instead.

### 6. A parked aircraft is under the ceiling too

New to this scenario, and a good illustration of what changing the arrival test
costs you. `z <= suppress_altitude` is satisfied by a drone resting on its
landing gear at 0.18 m, so a fire lit near a launch point was scored by an
aircraft that had not moved yet: **two of thirty-one drops in a run were
awarded four seconds before anybody took off.**

The fix is a floor as well as a ceiling. The band is a cheap way of saying
"flying, and low" — which is the thing actually being tested — and it sits well
below `drop_altitude` and well above the height the airframe rests at.

### 7. Everyone bids against a board that has not heard anyone

The three aircraft become idle at much the same moment and decide within
**30 ms** of each other. The board is published at 10 Hz, so all three read
`crew = 0` on every fire and all three computed the same best choice — and went
to the same fire *every single time*, twice onto fires small enough that a crew
of three was the worst option available to any of them. Nothing was wrong with
the arithmetic. It was being handed a picture in which nobody else had moved.

The fix is that claims go on a **shared topic**, so each drone hears the other
two. A claim published after the board's `header.stamp` cannot be in that
board, so the two sources add without double-counting: the board carries every
claim the spotter had accepted by then, the heard-claims table carries the
rest, and a claim older than the board is already counted and drops out — which
is also how the table expires. With crews visible, the fleet spreads across
separate fires when the fires are similar and converges on the big one when it
is worth converging on.

### 8. Joining a fire that is nearly out is the best-paid thing you can do

`work_left / n` collapses as a job finishes, so a fire at 95% has an enormous
share-per-second and equal shares pay a full one for **turning up after it is
over**. Measured: a drone bombed a 7 alone for fourteen seconds, both others
joined it with 0.3 drone-seconds remaining, and it kept 2.33 of the 7.

Equal shares are the rule and the rule stays, so the fix is a **join deadline**:
a crewed fire stops accepting members once `~join_deadline` of its work is
done. It applies only to a fire that already has a crew — taking over an
abandoned job at 90% is fine, since there is nobody to take it from.

### The laser mast

Not a bug, but the same kind of measured number. The scanner sits on a **0.25 m
mast**, not in hector's stock laser variant, which hangs the Hokuyo 0.097 m
*below* `base_link` — inside the aircraft, where it returns its own `range_min`
across the sectors the landing gear occupies.

The height is the one thing here genuinely specific to aircraft: **a quadrotor
pitches in order to translate.** Nothing on the airframe is above z = +0.04, so
a 0.12 m mast is clear while hovering level and useless in flight — the rotor
tips are 0.396 m out, so 15° of pitch swings the far side of the scan plane
down 0.10 m, straight through the rotor disc. Measured at 0.12 m, exactly that
happened. 0.25 m keeps the plane clear to ~32°, which is where
`~self_hit_tilt` comes from.

## Arguments

`roslaunch uav_bushfire bushfire.launch gui:=false num_hotspots:=8`

| Arg | Default | Meaning |
|---|---|---|
| `gui` | `true` | Gazebo client. `false` is roughly twice as fast |
| `rviz` | `false` | RViz showing the fire ground and all three aircraft |
| `num_hotspots` | `5` | Fires burning at once. Keep it above the fleet size |
| `world_half_size` | `4.0` | Fires are lit inside this; the graded break starts at 4.6 |
| `collect_dist` | `1.00` | Horizontal bombing radius (m). Must contain the crew ring |
| `suppress_altitude` | `1.45` | Altitude ceiling (m). Must contain the crew stack |
| `min_drop_altitude` | `0.45` | Altitude floor, so a parked drone scores nothing |
| `drop_altitude` | `0.95` | Where the first crew member holds. Keep under the ceiling |
| `work_per_intensity` | `1.2` | Drone-seconds of bombing per point of value |
| `max_crew` | `3` | Most drones one fire will take |
| `join_deadline` | `0.7` | A crewed fire stops accepting members past this much of its work |
| `crew_separation` | `1.00` | Gap between neighbouring crew stations on the ring (m) |
| `crew_altitude_step` | `0.15` | How much higher each further crew member holds (m) |
| `commit_timeout` | `90.0` | Release a drone that has not been on station this long (s) |
| `cruise_altitude` | `2.0` | Transit altitude. The gap to the ceiling *is* the bombing run |
| `arrive_radius` | `0.60` | Switch from flying to station-keeping inside this |
| `linear_speed` | `1.2` | Transit speed (m/s) |
| `angular_gain` | `2.0` | Heading P-gain |
| `avoid_dist` | `1.6` | Avoidance activation range (m) |
| `stop_dist` | `0.9` | Full-stop range (m) |
| `obstacles` | 8 trees | `[[x, y, radius], …]` the spotter must not light a fire inside. **Keep in step with `worlds/bushfire.world`** — `make_bushfire_world` prints the list it built and refuses to write a world whose trunks have moved, but nothing checks this file against that one automatically |

Avoidance ranges are much wider than the TurtleBot3 ancestor's 0.45/0.25,
because stopping distance is what these numbers really encode: these drones
transit at four times the speed, and a multirotor has to pitch back to
decelerate, which costs distance a differential drive does not spend.

## Known limitations

**A drone that never turns up still gets paid.** The value is split between the
drones that *chose* the fire, exactly as specified, not between the ones that
did the work — so a crew member stuck in a thicket collects a full share of a
fire its crewmates put out. `~commit_timeout` bounds how long that can go on
and a rescued drone releases its fire itself, but within the timeout it is free
money. Paying by contributed drone-seconds would remove it, and would also
remove the reason to bother arriving early.

**Nothing stops the fleet all choosing badly at once.** Each drone hears the
others' claims and prices them in, which is enough to break the case where
everyone piled onto one fire (bug 7), but it is still a greedy sequential
auction and its outcome depends on who happens to decide first. Nobody
re-plans, either: a claim is binding, so a fleet that has committed to a poor
split flies it out.

**The aircraft only deconflict where they are standing.** Crew stations are
built to keep drones off each other over a fire, and fires are kept far enough
apart that two crews do not overlap, but nothing deconflicts two drones whose
*paths* cross — and with crews, three aircraft now regularly converge on the
same fire from three directions. The laser sees them (they are solid), so there
is incidental avoidance. In the treasure version, which had no tasking at all,
all three met once in a four-minute run; all three were respawned and flying
again four seconds later.

**A reactive controller has no plan.** It only avoids what it can currently
see, so a fire in a concave pocket can hold a drone up — and now it can hold a
whole crew up, since the others are committed to the same fire.
`~commit_timeout` and `~reignite_period` are the slow backstops; neither is a
path planner.

**The descent is blind downwards.** A horizontal laser says nothing about what
is below, so nothing prevents flying into the ground except `drop_altitude` and
`min_altitude` being honest numbers.

**Fires do not spread or grow.** A suppressed slot re-ignites elsewhere at a
fresh random intensity, so the fire ground is always the same size. Real
bushfire dynamics — unattended fires growing and seeding new ones — would be
the natural next step.

## Files

| | |
|---|---|
| `launch/bushfire.launch` | all three stages at once; every argument passes through |
| `launch/bushfire_world.launch` | 1. Gazebo + the stand |
| `launch/bushfire_fleet.launch` | 2. three aircraft + the fire spotter; owns the tuning |
| `launch/bushfire_rviz.launch` | 3. the view, attachable to a running incident |
| `launch/one_uav.launch` | one aircraft's airframe + suppressor + monitor |
| `scripts/fire_spotter` | the fire ground, the ledger, the work meter, the payout |
| `scripts/fire_suppressor` | the choice, the controller, the geofence, the scoreboard |
| `scripts/pose_fire_monitor` | passive logging |
| `msg/Hotspot.msg` | id, x, y, intensity, work, crew, share, station — **no z** on the fire |
| `msg/HotspotArray.msg` | every fire at once: the board drones choose from |
| `msg/FireClaim.msg` | a drone announcing the fire it has chosen |
| `urdf/quadrotor_laser_mast.gazebo.xacro` | hector's quadrotor + the laser mast |
| `worlds/bushfire.world` | **generated** — the stand, the break, the surrounding bush |
| `scripts/make_bushfire_world` | writes that world; refuses to break the obstacle list |
| `scripts/make_bushfire_textures` | the tiling textures, checked against the fire palette |
| `models/bushfire/` | those textures and their Ogre materials |
| `rviz/bushfire.rviz` | the whole incident in the shared `world` frame |

## Building

This package lives in `~/uav_ws` alongside hector and the two other UAV
packages, so nothing extra is needed to build it. If the workspace is not built
yet, see [Requirements and install](#requirements-and-install)
— none of the third-party trees are packaged for Noetic and the build is
two-stage.

```bash
source ~/uav_ws/src/uav_pick_place/setup_uav.bash
cd ~/uav_ws && catkin_make --pkg uav_bushfire
```

## Related packages

* `uav_pick_place` — the same airframe with a gripper,
  moving blocks between pads.
* `uav_voice_control` — that mission, flown by talking
  to it.
* `tb3_treasure` — the ground-robot ancestor of this package, in `~/catkin_ws`.
