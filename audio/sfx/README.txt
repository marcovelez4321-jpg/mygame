AUDIO DROP-IN FOLDERS
Every folder has a README.txt saying exactly what goes in it and how to name it.
Drag your WAVs into the matching folder with the listed names -- that's it.
Full design notes: AUDIO_DESIGN.md in the project root (section 4).
Godot crunches every WAV to the PS1 sound on import (22050 Hz, IMA-ADPCM), so
deliver everything at full quality.

body/       PRIORITY 1 -- ragdoll and corpse sounds
surface/    PRIORITY 2 -- one folder per material
gore/       PRIORITY 3 -- gore and the mutation
props/      prop-only sounds (breaking, etc.)
weapons/    gun sounds + shell casings
enemy/      enemy voices, one folder per enemy type
player/     your own movement and body sounds
hits/       hit marker / headshot / kill feedback
ambience/   background beds and random one-shots