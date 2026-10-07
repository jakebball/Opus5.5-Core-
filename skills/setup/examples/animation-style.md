# Animation Style

**Binding for every animation in the game**, written 2026-10-03 at the user's request: "can you add
an animation-style guide that talks about the fluid springy motion that nail driver has so we use
that for all animations going forward so i dont need to kep saying it". It covers viewmodel
clips, gun parts, reloads, enemy clips, props, effects and UI motion. `tech-design.md` § Hard
Rules points here, and the project skills `build-gun` and `animate-gun` read it before animating.

**The reference is the guns' reloads** (`weapons.md` § The Stud Driver, § The Jawbreaker, § The Scoop,
§ The Spin Cycle, § The Nitro and § The Hot Shot), after the user's last round of feedback on the first
two.

## The look

**One smooth, springy movement that never stops except on an impact.** It is never a string of
separate moves. Moves launch fast, overshoot a little and settle, and each beat flows into the next.
Something small is always happening, and the thing being moved and everything around it reacts.

## The rules

Each rule came from something the user turned down or asked for.

1. **One continuous motion.** No key eases to a full stop before the next begins, and nothing
   freezes while something else moves.
   - **The Stud Driver's first reload** stopped at every key and held the hand still while the spool
     spun: "it feels a bit rigid. the reloads should fee like a single fluid smooth motion".
   - **Both guns' reloads later failed the same way:** "the reloads still seem to RIGID. it should
     feel like one smooth springy movement not specific sections". Almost every hand key used an ease
     that lands at zero speed, so the hand stopped at each key; the Jawbreaker's empty reload had 17
     such stops.
   - **So hand and gun keys carry no landing ease.** The path passes through them, and a spring
     gives the bounce (§ The toolkit).
2. **Snappy, never slow.** Long, even glides read as slow motion: "his arm moves in slow motion…
   speed up the whole animation by adding more keyframes and juice without sacrifices on time".
   Keep the length and pack in more, quicker beats.
3. **Stop dead only at a real impact:** a slam, a seat, a slap, a hit. The motion into an impact
   arrives faster than an even pace would, then stops, pinned exactly to its key.
4. **Anticipation before every big beat:** a tuck before a swat, a lift before a slam, a dip
   before a throw.
5. **Follow-through after it:** an overshoot and settle, a pat after a slam, a little hand-back
   before the hand returns to the grip.
6. **Fill waits with small beats, not glides:** a hop off a fingertip, a stir while something
   spins, a tug to free something, a swipe that winds it.
7. **Everything reacts.** The gun jolts and recovers at each event, loose parts spring on every
   shot, and props rattle on recoil.
8. **The regular reload gets the most flair; the tactical one is the reduced version.**
   - **The empty, regular reload is the show,** with as much flair as it can carry: "for full reload
     he should spin the spool, as he throws it in the air and as it comes down he slams it into the
     gun", and for the Jawbreaker, "regular should be more flashy with him spinning the bottle in
     one hand before dumping the jawbreakers inside".
   - **The tactical reload keeps the rhythm and drops the show:** "tactical can look how it does".
   - **The two must look different,** not one compressed into the other: "tactical and regular
     reload should look diff". The user's rule for every gun: "tactical being reduced with reg reload
     having the max amount of flare on it".
   - **A gun that holds one round has only the regular reload.** It is always either loaded or
     empty, so a tactical reload could never play. For the Nitro: "skip tatical as this rpg has 1
     shot and the same reload for it all".
   - **Each gun's showpiece is its own.** The user turned down a drumstick twirl for the Hot Shot:
     "maybe dont twirling though a bunch of other guns do that what are some cool ideas that are
     different". Spins, twirls, throws and flips are taken. A new gun's flair comes from its own
     mechanism, like the Hot Shot plugging itself back in and heating up.
   - **The flair suits the gun.** For the starter gun: "remember this is a base gun stat wise". Its
     flair is a cheap tool misbehaving, not a trick.
9. **Physical-looking motion is animated, not simulated:** "it shouldnt be literaly physics, just
   animated to look like it". Fake the cues instead:
   - speed that follows a slope;
   - a bump and a rebound on arrival;
   - a chain of drops, each with a hop;
   - a decaying wobble.

   Springs used as easing toward a target are fine. Integrating gravity and resolving collisions
   is not. A fall written as a formula still counts as authored: the Nitro's bowling ball drops
   along a ballistic arc pinned to the end of its rail and to its seat. An ease into place had read
   as a snap: "the bowling ball doesnt look like its dropping on the rail but just sanpping to it".
10. **Start from the hook, and get weight from the motion.** An enemy's clip starts from what it
    carries: the Armored walks behind its shield, and the Boss waves the Ban Hammer. A plain walk
    read as "basic". A heavy thing gets weight from a bigger, slower stride and a settle at each
    footfall, not from speed alone.
11. **Show it the way the game plays it.** A preview of a full-auto gun holds the trigger. A demo
    that fired in bursts with pauses made the Jawbreaker read as a burst rifle: "is it a burst
    rifle?why are there stops and not a coinktous stream". Each animation gets its own labelled
    station in the server showcase, so none is missed: the user "only saw 1" when two reloads
    shared a stand.

## The toolkit

How the look is built in this project. Every animation is keyframes: poses at times, written as
data. The tools below only decide how the frames between keys are filled.

| Tool | Where | Use it for |
| --- | --- | --- |
| Spline through keys | `MotionPath.sample` | Hand, prop and gun paths. Keys sit at uneven times and are passed through, never landed on: Catmull–Rom tangents carry the speed through each one |
| Spring follower | `MotionPath.follower` and `follow`: second-order dynamics, y + k₁y′ + k₂y″ = x + k₃x′ | Everything a hand or the gun does. It chases the keyed path, overshoots, settles and overlaps the next beat, which turns a list of keys into one springy movement |
| Shared smoothing | `MotionPath.handFollowers`, `gunFollowers`, `sampleHand` and `sampleGun` | Every reload calls these, so the smoothing is identical on every gun and tuned in one place |
| Pins | `MotionPath.pinWeight` and `pin`, on keys marked `impact` or `pin` | Impacts and catches. The spring is blended onto the keyed pose so that the contact lands exactly, then released |
| Rotation blending | `MotionPath.rotationVector`, `unwrap` and `fromRotationVector` | Hand orientation, blended as one rotation from the grip and unwrapped from key to key, so the wrist always turns the short way |
| Slam and impact keys | A `slam` ease (p²) into a key marked `impact` | Arriving faster than an even pace, then stopping dead |
| Rest keys | A key marked `rest` | A deliberate hold at the end, the only other place speed reaches zero |
| Nudges and twists | Small offsets on a key | Anticipation, tugs, hops, shakes and pats on top of a pose |
| Snap ease and overshoot | `MotionPath.ease("snap")`, 1 − (1 − p)³, and back ease-out | Mechanical parts only: a lid flipping, a cap popping, a crank spinning down. Never on hand or gun keys, where each one is a stop |
| Damped springs as easing | `DefaultViewmodel` shot motion, the gun's dip, the Jawbreaker's queue | Reactions that build up under repeated hits instead of restarting |
| Event kicks | An impulse into a spring at an event | The gun jolting on an eject, a seat, a shake or a pat |
| Decaying wobble | amplitude × e^(−t/τ) × sin(ωt) | Rattles and jiggles |
| Gravity drop | p² toward a lower spot, then a small sine hop | Things falling into place |
| Ballistic drop | p(t) = p₀ + v₀t + ½gt², with v₀ = (p₁ − p₀)/T − ½gT so that it lands on its seat at T, and g solved so that it leaves along the slope it rolled down | A ball leaving a rail or a ledge, so that the fall carries the roll's speed and direction |
| Rolling without slipping | A turn of distance ÷ radius about up × the direction of travel. Start the prop turned back by the whole roll's rotation, and it lands the way up it was built | A ball rolling along a rail, with its markings rolling with it |
| Cant toward the support hand | A roll on the gun track while the hand works on the gun's near side | Tilting the whole viewmodel so the left arm rises from the bottom corner instead of crossing the screen |
| Low elbow | The reload's elbow pole set far down in camera space | A forearm that rises from below rather than lying across the view |
| A prop on a pivot follows the hand | The prop points from its pivot at the point under the palm, solved as a pitch and a yaw | A part on a cord or a hinge that the hand carries, so it never leaves its pivot |
| In-between turn keys | A key's rotation blended part of the way toward another pose (`toward` and `share` in `HotShotReload`) | Spreading a big wrist turn over several frames |

**Values that worked:**

| Value | Setting | Seen on |
| --- | --- | --- |
| Beat spacing | Mostly 0.05–0.2 s | 23 hand keys in the Stud Driver's 2.8 s reload |
| Hand speed on an action | 10–14 studs/s | The same, measured per frame |
| Hand spring | 5 Hz, damping 0.5, response 1.8 | Both guns' reloads |
| Wrist spring | 3.6 Hz, damping 0.6, response 1 | Both guns' reloads |
| Gun spring | 3 Hz, damping 0.42, response 1.2 | Both guns' reactions during a reload |
| Pin | 0.05 s in, held 0.03 s, 0.07 s out | Slaps, seats, pats and the spool's catch |
| Overshoot on mechanical parts | Back ease 1.0–1.5. Below about 1 it barely shows: 0.3 peaks 0.2% past the target, and 1.2 about 5% | The Jawbreaker's lid and cap; the Spin Cycle's end cap, about 10° past a 185° stop at 1.2 |
| Spring damping ratio | 0.38 (gun dip) to 0.62 (Jawbreaker queue) | Lower bounces more |
| Spring frequency | π ÷ the motion's time for shot motion; 22 rad/s for the gun's dip and the Jawbreaker queue | |
| Gun reaction size | 0.02–0.05 studs and 0.02–0.22 rad | The reloads' gun tracks |
| Drop hop | 16% of the drop, over 0.08 s | The Jawbreaker's globe |
| Rattle | 0.004 studs, decaying over 0.09 s | The Jawbreaker's globe on each shot |
| Hand-driven spin | The stroke over the radius while the palm is on it, then a coast on a snap ease whose starting speed matches: 165° per 0.3-stud stroke on a 0.104 ring, about 1,900°/s at release, at rest 0.4 s later | The Scoop's focus ring |
| Spin-up and coast | A first-order lag toward the target speed, v += (v* − v)(1 − e^(−Δt/τ)): τ 0.08 s up and 0.5 s down, 1,200°/s while firing, held 0.12 s after the last shot | The Spin Cycle's barrels |
| Shudder | 23 Hz, 0.006 studs and 0.016 rad, in over 0.08 s and out over about 0.8 s | The Spin Cycle's spin-up |
| Roll along a rail | A cubic Hermite in distance, from the push's speed to the speed it leaves at: about 1.85 studs of rail in 0.6 s, pushed off at 1.8 studs/s | The Nitro's bowling ball |
| Drop off a rail | 0.15 s for about 0.15 studs down and 0.25 across. The solved gravity comes out near 10, and the arc leaves at the rail's slope, 8° down | The Nitro's bowling ball |
| Settle after a drop | A hop of 0.03 studs over the first 40%, and a rock of 0.022 studs decaying as (1 − p)² over a cycle and a half, in 0.28 s | The Nitro's bowling ball |
| Cant | 0.32 rad as the hand leaves the stick, 0.52–0.54 through the grab and lift, 0.48 at the slam, level 0.33 s after it | The Hot Shot's plug beat |
| Elbow pole in a reload | (−0.7, −2.6, −0.2) in camera space, against (−2, −1, −1) on the other guns | The Hot Shot's reloads |
| A part popping off | A snap-eased hop of 28°, a swing out to the side, a p² drop to hang 55° below level, then a wobble of 16° decaying over 0.16 s at 3.1 Hz | The Hot Shot's plug on the last shot |
| A light going out and coming back | Out over 0.5 s with a decaying flicker; back over 0.3 s, flickering at 17 Hz | The Hot Shot's tip and power light |
| Ammo feed | A spring at 30 rad/s with damping 0.55, one notch a shot | The Hot Shot's glue stick |
| Heartbeat | A 2.2 s cycle: a squeeze of −0.45 at 0, a lub of 1 at 0.12 s and a dub of 0.6 at 0.4 s, each a kick into a spring | The asteroid |
| Heave spring | 2.4 Hz, damping 0.34, divided by its first peak so a kick of 1 peaks at 1; 2.6 studs on the crust | The asteroid's crust |
| Ringing parts | 2 to 3.2 Hz, damping 0.2, 2.4° to 4.2°, the smaller parts faster and further | The asteroid's spires |
| Glow flash | (1 − e^(−t/0.025)) · e^(−t/0.3): at rest 60%, a dip before the beat, 100% at the peak, with a flicker of about 6% | The asteroid's cracks and mouth |
| Travelling wave | Each part delayed by its distance from the source: 240 studs/s over the rock, 140 studs/s down the spill | The asteroid |
| Twitch | A 3.5% chance in each 0.3 s slot of a kick at 4.5 Hz, 30% the size of a beat | The asteroid's crust between beats |

## Checking it before it is shown

- **Trace the speed of the moving thing per frame.** For a hand at viewmodel scale:
  - stretches under about 1 stud/s that go on for a while read as slow motion;
  - single-frame jumps over about 0.4 studs read as pops.
- **Count the stops.** A frame where the hand's speed dips below a quarter of the surrounding
  quarter-second's average, outside an impact, is a stop. Stops at plain keys are what read as
  sections. The springs took the Jawbreaker's empty reload from 17 stops to 6 and its tactical from
  11 to 5. The ones left are deliberate reversals: anticipation dips, shakes and tugs.
- **Watch the wrist.** A turn of more than about 45° in one frame reads as a flip. Blending the
  wrist as separate finger and palm directions flipped the Stud Driver's swat by 147° and the
  Jawbreaker's throw by 168°.
- **Check contacts under the spring.** Measure how far the sprung hand is from each contact key; pin
  any contact that must land exactly. A throw keeps its grip and lets the prop tumble after release.
- **Count the frames on fast loops.** Anything circling a loop needs at least about ten frames per
  lap at 60 fps, or it strobes. That capped the Jawbreaker's rolling speed near 3 studs/s round a
  0.6-stud coil.
- **A spin reads only with a mark.** Ridges or spokes all alike alias once a part turns more than
  half their spacing in a frame. The Scoop's focus ring has 16 ridges and spins at about 30° a frame,
  so a single tape tab is what shows it turning.
- **Check that the arm reaches its keys.** Measure the hand against its target every frame of a
  reload, and a held grip over several seconds. A solver that reads back what it wrote can creep: the
  viewmodel's elbow drifted until the hand fell 0.35 studs short (`weapons.md` § The left hand holds
  the gun), and the reloads had been tuned against the drifted arm.
- **Put an approach pose a little off the surface it touches.** The spring carries the hand past it.
  The Scoop's reach pose sat flush with the ring, so the hand tapped the ring and bounced off before
  the swipe.
- **No visible pops.** A hand-off, a respawn or a swap happens inside solid geometry, off screen,
  or under a fade.
- **Look from where the player looks:** first person for viewmodels, the deck for enemies, in the
  real idle pose.
- **Keep the action in view.** A viewmodel hand is about the size of the Jawbreaker's globe. Hold
  props on the side away from the camera, open lids away from it, and throw things away from it; the
  Jawbreaker's first pour was hidden behind the hand and the lid.
- **Sync contacts with what they move.** A lid, a cap or any part a hand drives waits for the hand
  to arrive; a lid on its own track closed before the palm reached it.
- **A part the hand lets go of moves once the hand is clear.** The Spin Cycle's cap opens only as the
  palm bounces off it, like a push latch. Opened at the slap, it would have swung into the recoiling
  palm. It also closes just before the slam lands, so the palm meets it shut.
- **Check a prop that moves on its own against the gun as well.** The Nitro's ball was tested as a
  sphere against the gun's triangles through its roll, fall and settle, so that it never sinks into a
  rail or the tip.
- **Check the hand against the gun as a box.** The viewmodel's hand is about 0.39 × 0.32 × 0.41
  studs. Test it against the gun's triangles at every key pose and along the moves between them
  before the clip runs. Then test it on captured frames, with the moving parts at their captured
  angles. On the Spin Cycle this found the straight path from the jug to the cap running through the
  magazine; a wind-up that drops out and down first clears it.
- **Keep each pose well under 180° from the one before it.** The hand's turn is blended as a rotation
  vector, which flips near 180°. The Hot Shot's pocket pose sat 151° from its grip, and the wrist then
  turned 132° in a single frame. Turned to about 55° from the grip, the worst turn fell to 15° a frame.
- **Spread a big turn over in-between keys.** A 137° wrist turn squeezed in after a pin released
  spiked at 54° a frame. Two keys turned 30% and 70% of the way spread it out.
- **Measure how much of the screen the arm covers.** Working on the gun's near side at pistol range,
  the Hot Shot's forearm lay across two-thirds of the screen's width. A cant and a low elbow took it
  down to a bottom-left corner of about a quarter.
- **Keep the payoff in view.** The arm was still over the nozzle when the Hot Shot's tip glowed back
  up, so the hand now leaves straight after the slam.
- **Start a prop's effect on the gun only once it is lined up.** The Hot Shot's shove counted from the
  moment the fresh stick appeared, so the old stick vanished into the boot while the new one was still
  at the hip.
- **Freeze a frame for pictures.** Snap a busy moment rather than hoping a capture lands on one.
  Render it offline from a private copy (`node tools.js shot --freeze` for a gun's reload), never by
  stopping a shared preview and moving Studio's camera (`greyout-map.md` § Checking assets).

## Reference implementations

- **The shared smoothing:** `mesh-source/lab/MotionPath.luau`. The spline, the eases, the spring
  follower, the pins and the rotation blending, used by every reload.
- **The Stud Driver's reloads:** `mesh-source/lab/GunMechanics.luau`, with the beat tables in
  `weapons.md` § The Stud Driver.
- **The Jawbreaker's reloads:** `mesh-source/lab/JawbreakerReload.luau`. A paintball-hopper pour
  whose shakes tip the container further as it empties, a slap that holds the lid open until the
  palm lands, and props held and thrown on the side away from the camera. The whole choreography is
  computed in the gun's own space.
- **The Scoop's reloads:** `mesh-source/lab/ScoopReload.luau`. A toss solved to land in the palm
  with a flip, a slam and a second press, and a focus ring that the palm spins at its own speed and
  that coasts after the hand leaves.
- **The Spin Cycle's reloads:** `mesh-source/lab/SpinCycleReload.luau`. Poses written in the frame
  of the magazine they touch, pours solved from each tube's mouth and axis, a token flip solved to land
  in the palm, a push-latch cap, and a spin-up with a shudder. Its barrels' spin-up and coast are in
  `SpinCycleMechanics`.
- **The Nitro's reload:** `mesh-source/lab/NitroReload.luau`. A ball spun on a fingertip, set on a
  rail with a bowling push, rolled without slipping along the rail's own path, dropped on a pinned
  ballistic arc and settled with a hop and a rock, while the hand slams the gear stick.
- **The Hot Shot's reloads:** `mesh-source/lab/HotShotReload.luau`. A stick carried into line on the
  bore's axis and pushed home, a plug that follows the hand round its cord's root and is slammed in
  while the gun cants toward the hand, and a heat-up with a flicker, a shudder, steam and a glob. The
  plug's pop and the light going out on the last shot are in `HotShotMechanics`.
- **Shot motion:** `DefaultViewmodel` (`weapons.md` § `DefaultViewmodel`). Springy parts on every
  shot, as data on each joint.
- **The Jawbreaker's feed:** `mesh-source/lab/JawbreakerFeed.luau`. Authored motion that looks
  physical: a roll speed that follows the track's slope, arrival rebounds, a spring-eased queue,
  cascading drops with hops, and recoil rattle.
- **The showcase:** `mesh-source/lab/GunMechanicsShowcase.luau`, a row of labelled stations per
  gun (`weapons.md` § The Stud Driver, The showcase).
- **Enemy clips:** `blender-source/PreviewRig.luau` (`enemies.md` § Enemy Types). Clips start from
  what each enemy carries.
- **A whole set piece:** `mesh-source/lab/AsteroidPulse.luau` (`brick-city-map.md` § The heartbeat).
  - **One clock drives everything:** a squeeze, a lub and a dub as kicks into springs, delayed by
    distance so the beat travels across the asteroid. Flashes rise fast and fade, twitches fill the gaps
    between beats, and a halo of bricks is kicked outward on each beat.
  - **The timing is data:** the generator writes each part's timing as attributes.
  - **The motion is pure functions of the clock,** so the Edit preview and a later client component share
    it.

## Related

- `art-direction.md` — how things look; this doc is how they move
- `weapons.md` — the guns, their reloads and the shot motion system
- `enemies.md` — the enemy rigs and their clips
- `.claude/skills/animate-gun/SKILL.md` — rigging a gun and making its reloads to this guide
