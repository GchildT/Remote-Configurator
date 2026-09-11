import React from "react";
import { Composition } from "remotion";
import { BFDashShort } from "./BFDashShort";

export const RemotionRoot: React.FC = () => {
  return (
    <Composition
      id="BFDashShort"
      component={BFDashShort}
      durationInFrames={900}
      fps={30}
      width={2160}
      height={3840}
    />
  );
};
