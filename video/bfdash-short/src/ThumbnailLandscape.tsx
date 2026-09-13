import React from "react";
import { AbsoluteFill, Img, staticFile } from "remotion";

// Native 16:9 (1920x1080) redesign of the vertical Short's thumbnail --
// not a scaled-down copy. Same fusion concept (Betaflight + EdgeTX logos
// converging into BFDash), but laid out to fill the wider, shorter frame:
// logos sit higher and further apart, the convergence point and title
// block are compressed vertically to fit 1080px of height instead of
// 3840px.
const GLOW = "0 0 24px rgba(56, 214, 255, 0.85), 0 0 4px rgba(56, 214, 255, 0.9)";

const LogoPlate: React.FC<{ src: string; side: "left" | "right"; logoScale?: number }> = ({
  src,
  side,
  logoScale = 1,
}) => (
  <div
    style={{
      position: "absolute",
      top: "6%",
      [side]: "8%",
      width: "26%",
      aspectRatio: "1 / 0.8",
      borderRadius: 28,
      background: "rgba(10, 18, 32, 0.55)",
      border: "3px solid rgba(56, 214, 255, 0.55)",
      boxShadow: "0 0 40px rgba(56, 214, 255, 0.35), inset 0 0 28px rgba(56, 214, 255, 0.12)",
      display: "flex",
      alignItems: "center",
      justifyContent: "center",
      padding: "8%",
    } as React.CSSProperties}
  >
    <Img
      src={src}
      style={{ width: "100%", height: "100%", objectFit: "contain", transform: `scale(${logoScale})` }}
    />
  </div>
);

export const ThumbnailLandscape: React.FC = () => {
  return (
    <AbsoluteFill style={{ backgroundColor: "#05070d" }}>
      <AbsoluteFill
        style={{
          background: "radial-gradient(circle at 50% 38%, rgba(56,214,255,0.22) 0%, rgba(0,5,15,0) 55%)",
        }}
      />

      <svg viewBox="0 0 1920 1080" style={{ position: "absolute", width: "100%", height: "100%" }}>
        <defs>
          <filter id="arcGlowL" x="-50%" y="-50%" width="200%" height="200%">
            <feGaussianBlur stdDeviation="8" result="blur" />
            <feMerge>
              <feMergeNode in="blur" />
              <feMergeNode in="SourceGraphic" />
            </feMerge>
          </filter>
        </defs>
        <path
          d="M 500 320 Q 800 430 960 500"
          fill="none"
          stroke="#38d6ff"
          strokeWidth={8}
          strokeLinecap="round"
          filter="url(#arcGlowL)"
        />
        <path
          d="M 1420 320 Q 1120 430 960 500"
          fill="none"
          stroke="#38d6ff"
          strokeWidth={8}
          strokeLinecap="round"
          filter="url(#arcGlowL)"
        />
        <circle cx={960} cy={500} r={16} fill="#ffffff" filter="url(#arcGlowL)" />
        <circle cx={960} cy={500} r={54} fill="none" stroke="#38d6ff" strokeWidth={3} opacity={0.6} filter="url(#arcGlowL)" />
      </svg>

      <AbsoluteFill
        style={{
          background: "radial-gradient(circle at 50% 46%, rgba(56,214,255,0.32) 0%, rgba(0,5,15,0) 20%)",
        }}
      />

      <LogoPlate src={staticFile("thumbnail/betaflight.png")} side="left" logoScale={1.6} />
      <LogoPlate src={staticFile("thumbnail/edgetx.png")} side="right" />

      <div
        style={{
          position: "absolute",
          top: "51%",
          left: "6%",
          right: "6%",
          textAlign: "center",
          fontFamily: "system-ui, sans-serif",
          fontWeight: 800,
          fontSize: 170,
          lineHeight: 1,
          color: "#ffffff",
          textShadow: GLOW,
        }}
      >
        BFDash
      </div>

      <div
        style={{
          position: "absolute",
          top: "76%",
          left: "10%",
          right: "10%",
          textAlign: "center",
          fontFamily: "system-ui, sans-serif",
          fontWeight: 700,
          fontSize: 52,
          lineHeight: 1.25,
          color: "#bfefff",
          textShadow: "0 0 16px rgba(56, 214, 255, 0.8)",
        }}
      >
        Tune your FPV Drone in the Field right from your Radio
      </div>

      <Img
        src={staticFile("brand/pfp-neontag-blue.png")}
        style={{
          position: "absolute",
          top: "6%",
          left: "50%",
          transform: "translateX(-50%)",
          width: "9%",
        }}
      />
    </AbsoluteFill>
  );
};
