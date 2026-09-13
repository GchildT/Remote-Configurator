import { describe, expect, it } from "vitest";
import { render } from "@testing-library/react";
import { beforeEach, afterEach } from "vitest";
import { TitleCard } from "./TitleCard";
import { mockFrameState } from "../../vitest.setup";

describe("TitleCard", () => {
  beforeEach(() => {
    mockFrameState.frame = 40;
  });

  afterEach(() => {
    mockFrameState.frame = 0;
  });

  it("renders the title and subtitle text, visibly", () => {
    const { getByText } = render(
      <TitleCard title="BFDash" subtitle="Remote Betaflight Configuration Dashboard" />,
    );
    const titleEl = getByText("BFDash") as HTMLElement;
    expect(titleEl).not.toBeNull();
    expect(titleEl.style.opacity).not.toBe("0");
    expect(getByText("Remote Betaflight Configuration Dashboard")).not.toBeNull();
  });
});
