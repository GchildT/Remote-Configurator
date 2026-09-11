import { describe, expect, it } from "vitest";
import { render } from "@testing-library/react";
import { BFDashShort } from "./BFDashShort";

describe("BFDashShort", () => {
  it("renders without throwing", () => {
    const { container } = render(<BFDashShort />);
    expect(container.firstChild).not.toBeNull();
  });
});
