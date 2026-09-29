// The token display symbol + formatting helpers. UI labels must use these,
// never a hardcoded symbol, so renaming the token is a one-line config change.
import { TOKEN_SYMBOL } from "@/lib/config";

// Rand-style display: "R12,000". The token is pegged to the South African
// Rand, so amounts read as money (prefix, thousands-separated, no decimals
// for whole amounts).
export function ges(n: number | string): string {
  const num = Number(n);
  return `R${num.toLocaleString(undefined, { maximumFractionDigits: 2 })}`;
}

export const SYMBOL = TOKEN_SYMBOL;