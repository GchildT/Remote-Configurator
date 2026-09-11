import { Easing, interpolate } from "remotion";

export const ICON_DRAW_FRAMES = 15;

export const getIconDrawProgress = (frame: number): number => {
  return interpolate(frame, [0, ICON_DRAW_FRAMES], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
    easing: Easing.out(Easing.cubic),
  });
};
