import React from "react";
import { AbsoluteFill, Easing, Img, interpolate, staticFile, useCurrentFrame } from "remotion";

const LOGO_POP_FRAMES = 15;
const SUBTITLE_DELAY_FRAMES = 20;
const SUBTITLE_POP_FRAMES = 15;

export const TitleCard: React.FC<{ title: string; subtitle: string }> = ({ title, subtitle }) => {
  const frame = useCurrentFrame();

  const logoProgress = interpolate(frame, [0, LOGO_POP_FRAMES], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
    easing: Easing.out(Easing.cubic),
  });

  const subtitleProgress = interpolate(
    frame,
    [SUBTITLE_DELAY_FRAMES, SUBTITLE_DELAY_FRAMES + SUBTITLE_POP_FRAMES],
    [0, 1],
    { extrapolateLeft: "clamp", extrapolateRight: "clamp", easing: Easing.out(Easing.cubic) },
  );

  return (
    <AbsoluteFill
      style={{
        backgroundColor: "#05070d",
        alignItems: "center",
        justifyContent: "center",
        flexDirection: "column",
        gap: 48,
      }}
    >
      <Img
        src={staticFile("brand/splash-neontag-blue.png")}
        style={{
          width: "70%",
          opacity: logoProgress,
          transform: `scale(${interpolate(logoProgress, [0, 1], [0.85, 1])})`,
        }}
      />
      <div
        style={{
          fontFamily: "system-ui, sans-serif",
          fontWeight: 700,
          fontSize: 56,
          color: "#bfefff",
          textShadow: "0 0 20px rgba(56, 214, 255, 0.8)",
          opacity: subtitleProgress,
          transform: `translateY(${interpolate(subtitleProgress, [0, 1], [16, 0])}px)`,
          textAlign: "center",
          padding: "0 10%",
        }}
      >
        {subtitle}
      </div>
      <div style={{ position: "absolute", opacity: 0, height: 0, overflow: "hidden" }}>{title}</div>
    </AbsoluteFill>
  );
};
