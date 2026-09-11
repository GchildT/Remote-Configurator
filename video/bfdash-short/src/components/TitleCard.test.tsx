import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { render } from "@testing-library/react";
import { TitleCard } from "./TitleCard";
import { mockFrameState } from "../../vitest.setup";

describe("TitleCard", () => {
  beforeEach(() => {
    // Well past LOGO_POP_FRAMES (15) and SUBTITLE_DELAY_FRAMES +
    // SUBTITLE_POP_FRAMES (35), so both pop-in animations have finished.
    mockFrameState.frame = 40;
  });

  afterEach(() => {
    mockFrameState.frame = 0;
  });

  it("renders the title and subtitle text", () => {
    const { getByText } = render(<TitleCard title="BFDash" subtitle="Remote Betaflight Configuration Dashboard" />);
    expect(getByText("BFDash")).not.toBeNull();
    expect(getByText("Remote Betaflight Configuration Dashboard")).not.toBeNull();
  });

  it("is actually visible (non-zero opacity) once pop-in animations finish", () => {
    // Regression test for the "BFDash never visible" defect: the old
    // assertions here only checked that the text existed in the DOM, which
    // passes even at opacity:0. Frame 0 (the vitest.setup.ts default before
    // this fix) has both title and subtitle fully transparent.
    const { getByText } = render(<TitleCard title="BFDash" subtitle="Remote Betaflight Configuration Dashboard" />);
    const titleEl = getByText("BFDash") as HTMLElement;
    const subtitleEl = getByText("Remote Betaflight Configuration Dashboard") as HTMLElement;
    expect(titleEl.style.opacity).not.toBe("0");
    expect(subtitleEl.style.opacity).not.toBe("0");
  });
});
