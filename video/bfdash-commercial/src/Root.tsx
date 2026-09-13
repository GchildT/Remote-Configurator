import React from "react";
import { Composition } from "remotion";
import { BFDashCommercial } from "./BFDashCommercial";

export const RemotionRoot: React.FC = () => {
  return (
    <Composition
      id="BFDashCommercial"
      component={BFDashCommercial}
      durationInFrames={1350}
      fps={30}
      width={3840}
      height={2160}
    />
  );
};
