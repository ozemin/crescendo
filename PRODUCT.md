# Product

## Register

product

## Users

Two friends on their own phones, same room or apart, evening ambient light,
playful-competitive mood. Turkish-speaking. They want to get into a match in
under 30 seconds: type a name, pick a pool, play. The web page is the playable
client until the native iOS app ships; a separate two-panel developer console
(`duel.html`) exists for testing and is not user-facing.

## Product Purpose

Crescendo is a real-time 2-player music guessing duel (best-of-5). Each round
both phones play the same 30s preview in sync while the album cover
de-pixelates; first correct answer wins the round. Success: matches feel
instant, synced, and fair; losing a round makes you want the next one.

## Brand Personality

Warm vinyl / analog. Record-shop intimacy, not arcade neon. Three words:
warm, tactile, competitive. The interface should feel like dropping a needle
on a record with a friend — cozy but with real stakes.

## Anti-references

- The 2025 AI default: violet/pink gradients, gradient wordmarks,
  glassmorphism cards, cold dark-slate SaaS chrome. (The old test console
  looked exactly like this; the player client must not.)
- Music-quiz kitsch: equalizer bars everywhere, neon note icons, Spotify
  green mimicry.
- Game-show shouting: no confetti storms, no bouncing buttons.

## Design Principles

1. **The record is the stage.** One centerpiece (the spinning record with the
   pixelating label) carries the personality; every control around it stays
   quiet and familiar.
2. **Thumbs first.** Every decision during play happens in the bottom half of
   a phone screen; answer targets are large and unambiguous.
3. **State is always spoken.** Queueing, buffering, counting down, locked,
   round lost — every state has one plain-Turkish line telling the player
   what is happening and what happens next.
4. **Warmth without mush.** Warm palette, but text contrast and answer
   feedback (right/wrong) stay unmistakably crisp.
5. **Latency honesty.** Sync moments (countdown, playback start) are driven
   by server time; the UI never fakes a state it hasn't reached.

## Accessibility & Inclusion

WCAG AA contrast (≥4.5:1 body text). Full `prefers-reduced-motion` support:
record spin and pixel-reveal animation replaced by static states with a
progress indicator. Answer feedback never relies on color alone (icons +
text). Touch targets ≥44px. Turkish UI copy throughout.
