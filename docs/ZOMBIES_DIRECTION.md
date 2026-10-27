# The new direction: Zombies in the Stacks (the user's, 2026-10-27)

This wins over docs/CLIMB_VISION.md and docs/WORLD.md wherever they disagree.
The open-world version is safe in git: tag `open-world-2026-10-27`.

## The idea
A slower, grounded shooter inspired by CoD Zombies, with our own twists. The
style, the eeriness and the original vision stay; only the gameplay changes.
- **Pace:** walking and sprinting, for now. The fast movement (bhops, dash,
  wall jumps, wings) is switched off rather than deleted.
- **Shooting:** heavier and more impactful, with immersive animations.
- **The grapple:** not something you start with (see Twists: a find).
- **The map:** the procedural Stacks, the whole map for now.
  - Their insides become grounded halls and rooms people once lived in, like
    the Ossuary's cathedral rooms.
  - The brutalist, absurd design stays, but **everything is walkable or
    mantleable**: no movement tricks needed anywhere (the user's).
- **Kept:** the Stalker and the quests, made more grounded, and as much of the
  open-world work as possible.

## Decided (the user's)
- **Map shape:** a cluster of towers joined by skybridges; you open bridges to
  cross between them.
- **Start:** the flooded depths under the towers. Tunnels lead up from them to
  a ground-floor lobby.
- **Horde:** mixed creatures. Infected people (with big ones) and rats, roaches
  and spiders in their own rounds.
- **Currency:** points for doors, guns and perks; scrap kept separate, for
  crafting barricades and traps.
- **Going down:** the Stalker's drag. Downed, you're dragged off, and
  teammates fight to get you back.

## Twists (the user's)
- **Through the windows:** the horde climbs the towers' outsides and breaks in
  through the window grid; you board windows up with scrap.
- **Ossuary Bell rounds:** the Ossuary walks past outside. Its bell starts a
  special round: the Bell-wraiths wake and the Consumed fly in.
- **Ritual Easter egg:** the quests, made grounded, become the steps toward
  ending the infection.
- **Mutations as perks, the Flesh Tree:**
  - The Flesh Tree stands in the middle of the towers, huge, towering above
    them all.
  - Its branches twist and turn round the buildings, gripping their corners
    like a squid's tentacles wrapping them up.
  - A player earns a mutation by eating enough meat or completing certain
    quests. Then mutation orbs grow at the ends of **every** branch, so they
    can never miss one.
  - Once that player grabs one and uses it, all the other orbs fade away.
- **Wandering trader box:** the rickshaw trader turns up somewhere new each
  round as the mystery box; rob him and he fights.
- **Climb to score:** opening your way upward into worse rounds; how high you
  got is your score.
- **The grapple as a find:** the virus arm is found or earned mid-match, like
  a wonder weapon.
- **Not chosen:** the power being out (generators lighting floors).

## The feel (the user's)
- **Speeds:** walking 4.5 m/s, sprinting 7 m/s.
- **Sprinting:** limited by the stamina bars, 1 bar every 2 s (about 8 s from
  full).
- **Aiming:** hold right mouse to aim down sights -- 1.2x zoom, moving at 60%
  speed.
- **Recoil:** brutal. A big kick, weapon sway and shake: every shot feels like
  a hit to you too.
- **The gun's weight:** heavy inertia. It lags behind your turns and swings
  back, bobs heavily with each step, and dips when you land or sprint.
- **Hits:** enemies flinch, and limbs can come off.
- **Later, once the new game's main structure is down:** Euphoria-like active
  ragdolls, like Max Payne 3 (a major project; the current ragdolls stay till
  then).

## The plan
1. **Setup:** the git tag (done); a zombies-mode main scene; a movement
   profile with the fast movement off.
2. **Feel:** walking and sprinting tuned; the heavy gunplay -- aiming down
   sights, recoil, weight, reloads, hit reactions.
3. **The map:** room pieces made in TrenchBroom (lived-in rooms) snapped
   together by the procedural Stacks; everything walkable or mantleable;
   boardable windows; doors and bridges with prices.
4. **The rounds:** spawning (through the windows), the round counter, the
   horde growing tougher, points, buying guns, the trader box, perks (the
   Flesh Tree), downs (the Stalker's drag).
5. **The eerie back in:** the Stalker, the Consumed and Bell rounds, the
   Ossuary outside, the quests as the Easter egg.
6. **Co-op testing.**

## Parked
The Terrain3D open world, the sky-high climbing traversal, the 1v1v1v1 race.

## Still to decide
Everything in each step, asked before it's built (Rule 10).

## The tentacle (the user's, 2026-10-27)
- **Yours from the start, on E:** hold E with the grapple's own indicator, animation and lunge out.
- **Grabbing an enemy:**
  - **The wrap:** procedural tendrils burst from the grabbed spot and coil round its body like Venom (TentacleWrap).
  - **The hold:** it's held as a live ragdoll 2.6 m in front of you. Its torso follows your aim; its arms and legs dangle.
  - **The cost:** one stamina bar. Bigger attacks will cost more (later).
  - **Letting go:** E again lets go, and it flies on with your swing: a throw.
- **Impacts (by speed):** a swung, thrown or knocked body flying into another enemy hurts both.
  - Struck: 6 damage for every m/s over 6 m/s, and knocked down too, or killed.
  - The flying body: half that.
  - Slamming into the world hurts it the same.
- **Knockdown:** a knocked-down enemy is a full ragdoll. It gets back up after 3 s once it's lying still, easing out of its pose into its animation (no get-up clip yet).
- **Picks of mine to tune:** knockdown 3 s, impacts from 6 m/s at 6 a m/s, the hold at 2.6 m, a 30 m/s top swing speed.
- **To come:** absorbing a held enemy, tearing it apart with the coils, more attacks and their stamina costs, a get-up animation, and Euphoria-like active ragdolls later.
