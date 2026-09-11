import React from "react";
import { AbsoluteFill, Img, staticFile, useCurrentFrame } from "remotion";
import type { CalloutRect, FocalPoint } from "../scenes";
import { CalloutBox } from "./CalloutBox";
import { getKenBurnsScale } from "./PhotoBeat.timing";

export const PhotoBeat: React.FC<{
  image: string;
  durationFrames: number;
  focalPoint: FocalPoint;
  calloutRect?: CalloutRect;
  dim?: boolean;
}> = ({ image, durationFrames, focalPoint, calloutRect, dim = false }) => {
  const frame = useCurrentFrame();
  const scale = getKenBurnsScale(frame, durationFrames);

  return (
    <AbsoluteFill style={{ overflow: "hidden", backgroundColor: "#05070d" }}>
      <Img
        src={staticFile(image)}
        style={{
          position: "absolute",
          width: "100%",
          height: "100%",
          objectFit: "cover",
          objectPosition: `${focalPoint.xPct}% ${focalPoint.yPct}%`,
          transform: `scale(${scale})`,
          filter: "contrast(1.12) saturate(1.08) brightness(0.92)",
        }}
      />
      <AbsoluteFill
        style={{
          background:
            "radial-gradient(circle at 50% 45%, rgba(0,0,0,0) 40%, rgba(0,5,15,0.85) 100%)",
        }}
      />
      {dim && (
        <AbsoluteFill style={{ backgroundColor: "rgba(2, 6, 15, 0.55)" }} />
      )}
      {calloutRect && <CalloutBox rect={calloutRect} durationFrames={durationFrames} />}
    </AbsoluteFill>
  );
};
