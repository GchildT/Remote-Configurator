import { describe, expect, it } from "vitest";
import { render } from "@testing-library/react";
import { BFDashCommercial } from "./BFDashCommercial";

describe("BFDashCommercial", () => {
  it("renders without throwing", () => {
    const { container } = render(<BFDashCommercial />);
    expect(container.firstChild).not.toBeNull();
  });
});
