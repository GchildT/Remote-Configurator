import { Easing, interpolate } from "remotion";

export const WORD_STAGGER_FRAMES = 2;
export const WORD_POP_FRAMES = 8;

export const splitIntoLines = (caption: string): string[][] => {
  return caption.split("\n").map((line) => line.trim().split(/\s+/));
};

export interface WordStyle {
  opacity: number;
  translateY: number;
  scale: number;
}

export const getWordStyle = (frame: number, wordStartFrame: number): WordStyle => {
  const localFrame = frame - wordStartFrame;
  const progress = interpolate(localFrame, [0, WORD_POP_FRAMES], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
    easing: Easing.out(Easing.cubic),
  });

  return {
    opacity: progress,
    translateY: interpolate(progress, [0, 1], [12, 0]),
    scale: interpolate(progress, [0, 1], [0.85, 1]),
  };
};

export const getWordStartFrame = (lineIndex: number, wordIndex: number, wordsBeforeThisLine: number): number => {
  return (wordsBeforeThisLine + wordIndex) * WORD_STAGGER_FRAMES;
};
