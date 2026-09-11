import React from "react";
import { useCurrentFrame } from "remotion";
import type { CalloutRect } from "../scenes";
import { getCalloutOpacity, getCalloutScale } from "./CalloutBox.timing";

export const CalloutBox: React.FC<{ rect: CalloutRect; durationFrames: number }> = ({
  rect,
  durationFrames,
}) => {
  const frame = useCurrentFrame();
  const opacity = getCalloutOpacity(frame, durationFrames);
  const scale = getCalloutScale(frame, durationFrames);

  return (
    <div
      style={{
        position: "absolute",
        left: `${rect.xPct}%`,
        top: `${rect.yPct}%`,
        width: `${rect.wPct}%`,
        height: `${rect.hPct}%`,
        opacity,
        transform: `scale(${scale})`,
        border: "6px solid #38d6ff",
        borderRadius: 32,
        boxShadow: "0 0 40px rgba(56, 214, 255, 0.9), inset 0 0 24px rgba(56, 214, 255, 0.5)",
      }}
    />
  );
};
