import { vi } from "vitest";
import React from "react";

vi.mock("remotion", async () => {
  const actual = await vi.importActual<typeof import("remotion")>("remotion");
  return {
    ...actual,
    useCurrentFrame: () => 0,
    Img: ({ src, style }: any) => React.createElement("img", { src, style }),
    AbsoluteFill: ({ children, style }: any) => React.createElement("div", { style }, children),
  };
});
