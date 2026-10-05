AUDIO DROP-IN FOLDERS
Every folder has a README.txt saying exactly what goes in it and how to name it.
Drag your WAVs into the matching folder with the listed names -- that's it, the
game picks them up automatically (new variations too).
Full design notes: AUDIO_DESIGN.md in the project root (section 4).
Godot crunches every WAV to the PS1 sound on import (22050 Hz, IMA-ADPCM), so
deliver everything at full quality.

LIVE NOW (drop files in and they play):
  body/                ragdoll and corpse sounds
  player/              jump, land, dash, wall jump, mantle, hurt, death, pickup
  weapons/pistol, machine_gun, shotgun/   fire, reload, switch per gun
  enemy/base, rusher, gunner/             idle, pain, death, attack per type
  hits/                hit tick, headshot, kill confirm, artery kill, gory kill
  gore/spurt_loop      the artery spray
  surface/concrete/    footsteps (step) for everyone, and the ground layer under bodies
  ambience/            oneshot_anylevel_## (random, subtle), optional bed_anylevel_loop_##

COMING LATER (folders ready, the systems that play them aren't built yet):
  surface/metal, wood, dirt   per-material footsteps and impacts
  gore/twitch, burst_big, splat_small
  props/
  weapons/casings/

Every folder has its own volume slider: pause menu > Audio.
