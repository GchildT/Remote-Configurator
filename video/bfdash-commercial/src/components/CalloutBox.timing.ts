import { interpolate } from "remotion";

export const CALLOUT_FADE_FRAMES = 5;

export const getCalloutOpacity = (frame: number, durationFrames: number): number => {
  const fadeIn = interpolate(frame, [0, CALLOUT_FADE_FRAMES], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });
  const fadeOut = interpolate(
    frame,
    [durationFrames - CALLOUT_FADE_FRAMES, durationFrames],
    [1, 0],
    { extrapolateLeft: "clamp", extrapolateRight: "clamp" },
  );
  return Math.min(fadeIn, fadeOut);
};

export const getCalloutScale = (frame: number, durationFrames: number): number => {
  return interpolate(frame, [0, CALLOUT_FADE_FRAMES], [0.92, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });
};
