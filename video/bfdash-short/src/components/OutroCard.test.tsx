import { describe, expect, it } from "vitest";
import { render } from "@testing-library/react";
import { OutroCard } from "./OutroCard";

describe("OutroCard", () => {
  it("renders both outro lines", () => {
    const { getByText } = render(
      <OutroCard caption={"Subscribe for more FPV builds & tuning\nLink in bio · comments open"} />,
    );
    expect(getByText("Subscribe")).not.toBeNull();
    expect(getByText("open")).not.toBeNull();
  });
});
