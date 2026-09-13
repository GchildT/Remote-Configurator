import React from "react";
import { useCurrentFrame } from "remotion";
import { getWordStartFrame, getWordStyle, splitIntoLines } from "./Caption.timing";

export const Caption: React.FC<{ text: string; startFrame: number; position?: "top" | "bottom" | "center" }> = ({
  text,
  startFrame,
  position = "top",
}) => {
  const frame = useCurrentFrame() - startFrame;
  const lines = splitIntoLines(text);
  let wordsBeforeThisLine = 0;

  const positionStyle: React.CSSProperties =
    position === "center"
      ? { position: "relative" }
      : {
          position: "absolute",
          left: "8%",
          right: "8%",
          ...(position === "top" ? { bottom: "54%" } : { top: "54%" }),
        };

  return (
    <div
      style={{
        ...positionStyle,
        display: "flex",
        flexDirection: "column",
        alignItems: position === "center" ? "center" : undefined,
        gap: 24,
        fontFamily: "system-ui, sans-serif",
        fontWeight: 800,
        fontSize: 96,
        lineHeight: 1.15,
        color: "#ffffff",
        textAlign: position === "center" ? "center" : undefined,
        textShadow: "0 0 24px rgba(56, 214, 255, 0.85), 0 0 4px rgba(56, 214, 255, 0.9)",
      }}
    >
      {lines.map((words, lineIndex) => {
        const lineStartOffset = wordsBeforeThisLine;
        wordsBeforeThisLine += words.length;
        return (
          <div
            key={lineIndex}
            style={{
              display: "flex",
              flexWrap: "wrap",
              justifyContent: position === "center" ? "center" : "flex-start",
              gap: "0 20px",
            }}
          >
            {words.map((word, wordIndex) => {
              const wordStartFrame = getWordStartFrame(lineIndex, wordIndex, lineStartOffset);
              const style = getWordStyle(frame, wordStartFrame);
              return (
                <span
                  key={wordIndex}
                  style={{
                    display: "inline-block",
                    opacity: style.opacity,
                    transform: `translateY(${style.translateY}px) scale(${style.scale})`,
                  }}
                >
                  {word}
                </span>
              );
            })}
          </div>
        );
      })}
    </div>
  );
};
