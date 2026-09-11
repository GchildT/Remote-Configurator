import { Easing, interpolate } from "remotion";

export const KEN_BURNS_START_SCALE = 1.0;
export const KEN_BURNS_END_SCALE = 1.08;

export const getKenBurnsScale = (frame: number, durationFrames: number): number => {
  return interpolate(frame, [0, durationFrames], [KEN_BURNS_START_SCALE, KEN_BURNS_END_SCALE], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
    easing: Easing.out(Easing.cubic),
  });
};
