# WELLSPRING

A single-file browser arcade game. No build step, no dependencies, no assets —
open `wellspring.html` in any modern browser and play.

## The idea

Most flying games give you a thruster. This one doesn't.

Your ship has no engine you can steer. It drifts on a solar current that only
ever gets faster. The one thing you control is **space itself**: hold anywhere
to tear open a **gravity well**, and the ship falls toward it. Invert the well
and it shoves the ship away instead.

So you never move the ship. You place the thing the ship falls toward, and then
you live with the trajectory you just committed to. Aiming becomes a matter of
leading your own momentum — put the well where you want to *end up swinging*,
not where you want to be.

## Controls

| Action | Mouse / keyboard | Touch |
| --- | --- | --- |
| Open an attracting well | hold left mouse | hold one finger |
| Invert it (push away) | right mouse, or hold `Shift` | hold two fingers |
| Start / restart | click or `Space` | tap |
| Pause | `P` or `Esc` | — |
| Mute | `M` | — |

## Scoring

- **100 × combo** for each pylon gate you thread.
- **45 × combo** per charge mote scooped.
- **30 × combo** for a *graze* — passing within a hair of a pylon.
- **20 × combo** for grazing drifting rubble.
- A slow trickle of points for raw depth survived.

The combo multiplier climbs to ×9 and decays if you play it safe, so the
scoring pushes you to fly closer to things than is comfortable.

## Charge

Holding a well burns charge, and an empty well won't hold you. Motes refill it,
and it trickles back on its own when you let go. The real skill is learning to
*pulse* the well in short taps instead of leaning on it — a held well is both
expensive and hard to aim out of.

## Design notes

Two physics details do a lot of the work:

- **Drag is relative to the moving medium, not the world.** Left completely
  alone the ship settles at exactly the speed of the current and holds station
  on screen. Every bit of drift is therefore something *you* caused, which
  makes the controls feel honest rather than punishing.
- **Well falloff is quadratic and clamped to a radius.** Strength ramps up
  smoothly as the ship nears the core, so you can make tiny corrections at the
  edge of the well and violent slingshots at its centre with the same gesture.

The whole thing runs on a fixed 120 Hz physics step decoupled from rendering,
so behaviour is identical on a 60 Hz laptop and a 144 Hz monitor, and tabbing
away can't fling the ship through a wall. Audio is synthesised on the fly with
the Web Audio API — there are no sound files.

## Performance

The renderer is deliberately frugal, because a 2D canvas gets slow in very
specific ways. Measured with an instrumented canvas that counts every op:

| | before | after |
| --- | --- | --- |
| canvas ops / frame | ~1130 | ~500 |
| `shadowBlur` activations / frame | ~11 | 0 |
| worst case (death burst, 155 particles) | — | ~675 |
| game logic + draw dispatch | — | 0.12 ms / frame |

What actually mattered:

- **`shadowBlur` is gone.** It was the single most expensive call in the
  renderer — every glowing pylon lip, mote, and the ship re-blurred on each
  draw. Glows are now pre-baked once into small offscreen canvases and blitted.
- **The trail was 67 `stroke()` calls a frame**, one per segment. It is now
  four tapered bands, each a single path.
- **Gradients are cached.** The background, vignette and pylon bodies used to
  allocate fresh gradient objects every frame.
- **Stars and particles are batched** into a few colour/alpha buckets, so a
  150-particle burst costs a handful of state changes instead of 300.
- **Device pixel ratio is capped by window area.** At DPR 2 a large window
  means pushing 4x the pixels for no visible gain; the cap drops to 1.5 and
  then 1 as the window grows. This is usually the real fix for "it's laggy on
  my big monitor".

Particle counts, object pools, the ship trail and every cache are bounded, so
a long run can't leak. The pylon-gradient cache is keyed on *rounded* width
specifically because pylon widths are random floats and would otherwise grow
the map without limit.
