import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { render } from "@testing-library/react";
import { OutroCard } from "./OutroCard";
import { mockFrameState } from "../../vitest.setup";

describe("OutroCard", () => {
  beforeEach(() => {
    // Well past every word's pop-in (WORD_STAGGER_FRAMES * wordCount +
    // WORD_POP_FRAMES, at most in the mid-20s for this caption) and past
    // LOGO_PULSE_FRAMES (20).
    mockFrameState.frame = 40;
  });

  afterEach(() => {
    mockFrameState.frame = 0;
  });

  it("renders both outro lines", () => {
    const { getByText } = render(
      <OutroCard caption={"Subscribe for more FPV builds & tuning\nLink in bio · comments open"} />,
    );
    expect(getByText("Subscribe")).not.toBeNull();
    expect(getByText("open")).not.toBeNull();
  });

  it("is actually visible (non-zero opacity) once word pop-ins finish", () => {
    // Regression test for the "BFDash never visible" defect class: the old
    // assertion only checked that the text existed in the DOM, which
    // passes even at opacity:0 (true at frame 0, the old hardcoded mock).
    const { getByText } = render(
      <OutroCard caption={"Subscribe for more FPV builds & tuning\nLink in bio · comments open"} />,
    );
    const wordEl = getByText("Subscribe") as HTMLElement;
    expect(wordEl.style.opacity).not.toBe("0");
  });
});
