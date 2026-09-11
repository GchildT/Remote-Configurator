import React from "react";
import { AbsoluteFill, Easing, Img, interpolate, staticFile, useCurrentFrame } from "remotion";
import { Caption } from "./Caption";

const LOGO_PULSE_FRAMES = 20;

export const OutroCard: React.FC<{ caption: string }> = ({ caption }) => {
  const frame = useCurrentFrame();
  const logoScale = interpolate(frame, [0, LOGO_PULSE_FRAMES], [0.8, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
    easing: Easing.out(Easing.cubic),
  });

  return (
    <AbsoluteFill style={{ backgroundColor: "#05070d" }}>
      <AbsoluteFill style={{ alignItems: "center", justifyContent: "center", top: "-15%" }}>
        <Img
          src={staticFile("brand/pfp-neontag-blue.png")}
          style={{
            width: "45%",
            transform: `scale(${logoScale})`,
          }}
        />
      </AbsoluteFill>
      <Caption text={caption} startFrame={0} />
    </AbsoluteFill>
  );
};
