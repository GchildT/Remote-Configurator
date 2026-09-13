import { vi } from "vitest";
import React from "react";

// Mutable frame state that test files can set before rendering, so
// component tests can assert on post-animation state (e.g. opacity after a
// pop-in finishes) instead of only ever seeing frame 0. Import
// `mockFrameState` from this module and set `mockFrameState.frame = 40`
// before calling `render(...)`.
export const mockFrameState = { frame: 0 };

vi.mock("remotion", async () => {
  const actual = await vi.importActual<typeof import("remotion")>("remotion");
  return {
    ...actual,
    useCurrentFrame: () => mockFrameState.frame,
    Img: ({ src, style }: any) => React.createElement("img", { src, style }),
    AbsoluteFill: ({ children, style }: any) => React.createElement("div", { style }, children),
  };
});
