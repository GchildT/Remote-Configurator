import { describe, expect, it } from "vitest";
import { render } from "@testing-library/react";
import { TitleCard } from "./TitleCard";

describe("TitleCard", () => {
  it("renders the title and subtitle text", () => {
    const { getByText } = render(<TitleCard title="BFDash" subtitle="Remote Betaflight Configuration Dashboard" />);
    expect(getByText("BFDash")).not.toBeNull();
    expect(getByText("Remote Betaflight Configuration Dashboard")).not.toBeNull();
  });
});
