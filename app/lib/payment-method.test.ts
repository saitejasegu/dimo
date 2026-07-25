import { describe, expect, it } from "vitest";
import {
  paymentMethodIdForLabel,
  resolvePaymentMethodId,
  type PaymentMethodOption,
} from "@/lib/types";

const methods: PaymentMethodOption[] = [
  {
    id: "payment-method-cash",
    name: "Cash",
    type: "Cash",
    detail: "",
    archived: false,
    isDefault: false,
  },
  {
    id: "card-1",
    name: "Visa",
    type: "Card",
    detail: "42",
    archived: false,
    isDefault: true,
  },
];

describe("resolvePaymentMethodId", () => {
  it("keeps a valid requested id", () => {
    expect(resolvePaymentMethodId("payment-method-cash", methods)).toBe(
      "payment-method-cash",
    );
  });

  it("falls back to the account default when requested is missing", () => {
    expect(resolvePaymentMethodId(null, methods)).toBe("card-1");
    expect(resolvePaymentMethodId("", methods)).toBe("card-1");
    expect(resolvePaymentMethodId("gone", methods)).toBe("card-1");
  });

  it("falls back to Cash when no methods are available", () => {
    expect(resolvePaymentMethodId(null, [])).toBe("payment-method-cash");
  });
});

describe("paymentMethodIdForLabel", () => {
  it("resolves a UI label to a durable id", () => {
    expect(paymentMethodIdForLabel("Card · Visa · 42", methods)).toBe("card-1");
  });

  it("falls back to the default when the label is unknown", () => {
    expect(paymentMethodIdForLabel("Unknown method", methods)).toBe("card-1");
  });
});
