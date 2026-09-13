import React from "react";
import { AbsoluteFill, Img, staticFile } from "remotion";

// Same thumbnail design as the vertical Short, presented within a 16:9
// landscape canvas (standard YouTube thumbnail shape) for the commercial
// video. Thumbnail.tsx mixes percentage positioning with fixed-pixel font
// sizes, so a live CSS transform: scale() wrapper produced incorrect
// layout (text overlapping) under Remotion's AbsoluteFill nesting. Instead,
// this reuses the already-rendered, already-correct portrait PNG
// (public/thumbnail-static/portrait.png) and letterboxes that image --
// plain image scaling has no layout ambiguity, so it reproduces the design
// pixel-for-pixel, pillarboxed and centered.
export const ThumbnailLandscape: React.FC = () => {
  return (
    <AbsoluteFill style={{ backgroundColor: "#000000" }}>
      <Img
        src={staticFile("thumbnail-static/portrait.png")}
        style={{ width: "100%", height: "100%", objectFit: "contain" }}
      />
    </AbsoluteFill>
  );
};
