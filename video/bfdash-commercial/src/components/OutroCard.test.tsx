import { describe, expect, it, beforeEach, afterEach } from "vitest";
import { render } from "@testing-library/react";
import { OutroCard } from "./OutroCard";
import { mockFrameState } from "../../vitest.setup";

describe("OutroCard", () => {
  beforeEach(() => {
    mockFrameState.frame = 40;
  });

  afterEach(() => {
    mockFrameState.frame = 0;
  });

  it("renders both outro lines, visibly", () => {
    const { getByText } = render(
      <OutroCard caption={"Subscribe for more FPV\nLink in Bio - Comments Open"} />,
    );
    const wordEl = getByText("Subscribe") as HTMLElement;
    expect(wordEl).not.toBeNull();
    expect(wordEl.style.opacity).not.toBe("0");
    expect(getByText("Open")).not.toBeNull();
  });
});
