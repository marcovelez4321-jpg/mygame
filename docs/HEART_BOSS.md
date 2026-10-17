# The heart boss

The user's design, decided 2026-10-17. Rule 10: every detail and value here is the user's choice.

## The idea

A giant human heart chained up in a huge cathedral room at the top of a tower. It beats and drips blood, with immersive sound, animation and effects. The inspiration is GTA IV's hidden heart, chained up inside the Statue of Happiness.

Its attacks are rhythm-based, timed to a song: each kick and each snare drum fires a different attack. One of them is a beam of blood that blasts you backwards and hurts, like a laser.

## Built

### The cathedral (`StackBuilder._cathedral`)

- **Where:** on top of the hive (tower 5), built the way the procedural Stacks built their halls.
- **Size:** 500 m tall and 300 m across (280 m inside the walls). Floor at 4,304 m, roof at 4,824 m.
- **Inside:** the middle 160 m across is kept open for the heart and the fight. The rest of the hall's features stay round the walls.
- **Look:** the Stack's concrete, with the hive's growth creeping in round the floor's edges.
- **Ways in:**
  - up the top hall's panic stairs, through a hole in the floor;
  - a ragged 30 m gap, 165 m up one wall.
- **Windows:** two slits, 3 x 60 m, starting 10 m up, on opposite walls.
- **The hive below:** steps out to the cathedral in 4 tiers from 3,500 m.

### The models (credited in CREDITS.md)

- `art/heart_boss/realistic-human-heart/`
- `art/heart_boss/chain/`

### The blood beam (`BloodBeam`, `shaders/blood_beam.gdshader`)

The look comes from the Avatar State's glowing eyes and mouth (Aang).

- **The hole:** it tears open anywhere on the heart's surface. It glows white-hot for **one beat** as the warning, then fires on its drum hit.
- **The beam:** a white-hot core inside a red glow, **4 m** thick, with blood streaming along it. Droplets and red mist spray off it, and red light floods the room.
- **The blast:** it lasts **0.4 s** and stops at whatever it hits.
- **A hit:** **35** damage, and you're blasted backwards at **15 m/s**.
- **Co-op:** `Network.send_blood_beam` (the host deals the hits).

### The beat mapper (`scenes/tools/beat_mapper.tscn`, `BeatMap`)

Run the scene with F6 and load a song. Press Space to play, then tap 1 for kick, 2 for snare and 3 for hi-hat. Taps can snap to a BPM grid (1/16 notes) once you've set the BPM and where the first beat lands. The song's waveform runs under the lanes.

It saves a `BeatMap` (`.tres`, next to the song by default) holding the song, its BPM and first beat, and the times of every hit. The heart will read this file.

## Still to decide or build

- The song: one the user has rights to, ideally with its drum stems or MIDI. Then the beat map.
- Which drum fires which attack. The kick's attack, and any others.
- How players hurt it, its health, its phases, and what killing it gives.
- The chains: how many, and where they anchor.
- Its size and where it hangs.
- The sounds: heartbeat, chains, beam blast, drips.
- What happens if the song ends before it dies.
- Keeping TowerLife's swarms out of the cathedral.