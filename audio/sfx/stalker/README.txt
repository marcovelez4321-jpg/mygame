THE STALKER'S SOUNDS: drop your files in this folder.

Name each file after its slot, plus a number:
    hurt_01.wav, hurt_02.ogg, lure_01.mp3 ...
Every file whose name starts with a slot's name joins that slot. Each time
the Stalker does that thing it plays one of them at random. Add as many as
you like. A slot with no files stays silent (or keeps its old made-up
sound: the croak, the shriek, the help scream).

You can also drag clips into a slot by hand: open
audio/events/stalker/stalker_voices.tres, expand a slot and fill its
"clips". Each slot also has volume and pitch variation there.

THE SLOTS

Hurt
  hurt             shot (now and then, not every bullet)
  driven_off       hurt too much: it flees
  leaves           gone (it leaves for a while after fleeing)

Attacking
  lunge            lunging for you
  grab             it's got you
  dragging         while it drags you (every few seconds)
  thrown_off       you broke free (it throws you)
  dropped          done dragging: drops you hurt and runs

Stalking and hunting
  starts_stalking  starts stalking you (sometimes)
  starts_hunting   picks up your trail
  hunting          running your trail (now and then)
  flanking         starts flanking round behind you (full fear)
  turns_up         turns up again (back on your trail)
  fear_full        the fear meter's just filled

Seen and hiding
  spotted          you've seen it
  runs_away        it bolts for cover
  hiding           settled in hiding (sometimes)

Stunts
  croak_behind     the croak right behind you, nothing there
  help_scream      the far-off scream for help
  lure             "help me" / "follow me": out of sight nearby,
                   right behind you (whispered), or far off (echoing)
  behind_you       standing right behind you when you turn round
  watching         watching from the dark, off to the side
  ceiling_scuttle  scuttling across the ceiling at the edge of your view
  doorway_dash     skittering across your way ahead
  corpse_drag      dragging a body across your way
  leap             leaping between towers, far off

It's kept sparse: no voice within 6 s of the last (except hurt, lunge,
grab, being driven off, being thrown off and stunt sounds), and the
everyday ones only play some of the time.