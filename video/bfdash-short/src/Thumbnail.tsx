import React from "react";
import { AbsoluteFill, Img, staticFile } from "remotion";

const GLOW = "0 0 24px rgba(56, 214, 255, 0.85), 0 0 4px rgba(56, 214, 255, 0.9)";

const LogoPlate: React.FC<{ src: string; side: "left" | "right"; logoScale?: number }> = ({
  src,
  side,
  logoScale = 1,
}) => (
  <div
    style={{
      position: "absolute",
      top: "9%",
      [side]: "6%",
      width: "38%",
      aspectRatio: "1 / 0.85",
      borderRadius: 48,
      background: "rgba(10, 18, 32, 0.55)",
      border: "3px solid rgba(56, 214, 255, 0.55)",
      boxShadow: "0 0 60px rgba(56, 214, 255, 0.35), inset 0 0 40px rgba(56, 214, 255, 0.12)",
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

export const Thumbnail: React.FC = () => {
  return (
    <AbsoluteFill style={{ backgroundColor: "#05070d" }}>
      <AbsoluteFill
        style={{
          background: "radial-gradient(circle at 50% 40%, rgba(56,214,255,0.22) 0%, rgba(0,5,15,0) 55%)",
        }}
      />

      <svg
        viewBox="0 0 2160 3840"
        style={{ position: "absolute", width: "100%", height: "100%" }}
      >
        <defs>
          <filter id="arcGlow" x="-50%" y="-50%" width="200%" height="200%">
            <feGaussianBlur stdDeviation="10" result="blur" />
            <feMerge>
              <feMergeNode in="blur" />
              <feMergeNode in="SourceGraphic" />
            </feMerge>
          </filter>
        </defs>
        <path
          d="M 560 1000 Q 900 1350 1080 1620"
          fill="none"
          stroke="#38d6ff"
          strokeWidth={10}
          strokeLinecap="round"
          filter="url(#arcGlow)"
        />
        <path
          d="M 1600 1000 Q 1260 1350 1080 1620"
          fill="none"
          stroke="#38d6ff"
          strokeWidth={10}
          strokeLinecap="round"
          filter="url(#arcGlow)"
        />
        <circle cx={1080} cy={1620} r={20} fill="#ffffff" filter="url(#arcGlow)" />
        <circle cx={1080} cy={1620} r={70} fill="none" stroke="#38d6ff" strokeWidth={4} opacity={0.6} filter="url(#arcGlow)" />
      </svg>

      <AbsoluteFill
        style={{
          background: "radial-gradient(circle at 50% 42%, rgba(56,214,255,0.35) 0%, rgba(0,5,15,0) 22%)",
        }}
      />

      <LogoPlate src={staticFile("thumbnail/betaflight.png")} side="left" logoScale={1.7} />
      <LogoPlate src={staticFile("thumbnail/edgetx.png")} side="right" />

      <div
        style={{
          position: "absolute",
          top: "44%",
          left: "6%",
          right: "6%",
          textAlign: "center",
          fontFamily: "system-ui, sans-serif",
          fontWeight: 800,
          fontSize: 280,
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
          top: "57%",
          left: "7%",
          right: "7%",
          textAlign: "center",
          fontFamily: "system-ui, sans-serif",
          fontWeight: 700,
          fontSize: 100,
          lineHeight: 1.3,
          color: "#bfefff",
          textShadow: "0 0 20px rgba(56, 214, 255, 0.8)",
        }}
      >
        Tune your FPV Drone in the Field right from your Radio
      </div>

      <div
        style={{
          position: "absolute",
          bottom: "9%",
          left: "18%",
          right: "18%",
          height: 2,
          background:
            "linear-gradient(90deg, rgba(56,214,255,0) 0%, rgba(56,214,255,0.7) 50%, rgba(56,214,255,0) 100%)",
        }}
      />

      <Img
        src={staticFile("brand/pfp-neontag-blue.png")}
        style={{
          position: "absolute",
          bottom: "3%",
          right: "6%",
          width: "14%",
        }}
      />
    </AbsoluteFill>
  );
};
