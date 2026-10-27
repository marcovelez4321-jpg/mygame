# The Red Creep (the user's, 2026-10-27): the plan, decided

A sentient, mold-like red weed whose one goal is to spread through the Stack.

## Decided (the user's answers)
- **Start:** one bush per area of the Stacks demo: depths, tunnel, lobby, corridor, flats, stair hall, great hall, courtyard (not in the Flesh Tree's trunk). The bush looks like the open world RedWeed (`RedWeed._bush_mesh`).
- **Seeds:** anything that touches a bush or its ropes (enemies, the player) picks up seeds from the barbs. They fall off after a random 20 s to 3 min and start a new small bush there.
- **Growth:** ropes like the vines on the back of Grandma's house (RedWeed's creeper look), braided and intertwining. They squirm and creep across the ground like worms at about 1 m every 3 s. Each patch is capped at about 15 m across; only seeds take it further.
- **Reaching:** ropes near life (players, enemies) lift off the ground and reach for it.
- **The wrap:** on touch it holds the target and drains 5 hp/s, covering it completely in vines over 6 s. Then the target is frozen in place and drained to death unless freed.
- **Fighting it:** fire (fire barrels, explosions) burns it back; shooting cuts ropes and the cut piece withers. Shooting a cocoon frees whoever is inside.
- **Its mind:**
  - Bodies become nurseries: anything it drains to death, or any corpse its tips reach, becomes a new bush.
  - Drawn by noise and blood: gunshots, explosions and hits pull its tips that way, and it grows faster toward them.
  - Climbs to spread: it climbs walls and goes up through doorways and hatches to other floors, draping off ledges.
  - Patches link up: they send runners to each other, join into one network and pulse together. A cut runner withers beyond the cut.

## Built (2026-10-27)
- `scripts/zombies/red_creep.gd` (RedCreep, in the demo scene) handles the area bushes, seeds (barbs on the carrier), nurseries, noise and blood, links, the network pulse, the cocoons, and all the co-op messages (late joiners included).
- `scripts/zombies/red_creep_patch.gd` (RedCreepPatch):
  - the bush (RedWeed's, twice its size), and braided ropes crawling over floors and walls, over lips and down off ledges;
  - steering: wander, life, noise, its own edge, away from fire; forking;
  - tendrils reaching for life;
  - cutting and burning, with withering pieces;
  - one mesh per rope, rebuilt only when it changes (4 a frame at most).
- `scripts/zombies/red_wrap.gd` (RedWrap): the cocoon climbing its target, the hold (players: held_point; creatures: stopped and pinned), the drain, the freeze at full cover (no shooting; animation stopped), and 3 shots or fire to cut it free.
- `shaders/red_creep.gdshader`: the squirm and the network pulse.
- Hooks: WeaponController's shot paths cut ropes and draw it; Explosion burns it back and draws it.
- Headless test: 8 area bushes grew. A shot cut a rope. The test player was reached, wrapped, drained to death and grown over into a new bush. Creatures carried seeds, and a runner linked two patches.

## Values I picked (to confirm with the user)
- rope step 0.35 m, up to 10 ropes a patch, climbing up to 12 m above its bush;
- sensing life 10 m, reaching 4 m (tendrils at 1.6 m/s);
- noise and blood 25 m for 12 s, 1.5x faster;
- links within 30 m;
- at most 16 patches, at least 6 m apart;
- a stump regrows after 5 s; 3 shots free a cocoon.