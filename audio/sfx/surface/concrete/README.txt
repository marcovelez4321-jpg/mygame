CONCRETE SURFACE -- PRIORITY 2 (step and the impacts are LIVE)   (covers: concrete / stone / brick)
FORMAT: WAV, 44.1 or 48 kHz, 24-bit, MONO (sounds in the 3D world must be mono).
No silence at the start, short fade at the end, peaks around -1 dBFS.
Loops: seamless, cut on zero crossings.
Number each variation: name_01.wav, name_02.wav, ... (the counts are targets: fewer is fine to start, more variations sound better)

impact_soft_01 .. 04        an object made of concrete landing lightly
impact_hard_01 .. 04        an object made of concrete slamming into something
scrape_rough_loop_01        LOOP 2-4 s: it being dragged across a rough surface
scrape_smooth_loop_01       LOOP 2-4 s: it being dragged across a smooth surface
bullet_01 .. 04             a bullet hitting concrete
step_01 .. 08               footsteps on concrete

These also feed the ragdoll "ground layer": a body landing on concrete plays
impact_soft/impact_hard from here under the body thud.

For now ALL floors count as concrete, so step_## is everyone's footsteps and
impact_soft/impact_hard play under every body that lands.
