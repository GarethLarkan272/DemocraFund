import { createHmac } from "node:crypto";
import { privateKeyToAccount, PrivateKeyAccount } from "viem/accounts";

export const CUSTODY_SECRET = process.env.CUSTODY_SECRET ?? "dev-only-secret-change-me";

// A user's wallet is derived deterministically from the server secret and their
// stable id (username). The backend holds the key, so the user never signs or
// pays gas - their identity is still a real, attributable on-chain address.
export function deriveAccount(role: string, username: string): PrivateKeyAccount {
  const key = createHmac("sha256", CUSTODY_SECRET)
    .update(`${role}:${username}`)
    .digest("hex");
  return privateKeyToAccount(`0x${key}`);
}

export function deriveRoleWallet(role: "committee" | "payer" | "treasury"): PrivateKeyAccount {
  return deriveAccount(role, role);
}

// A company's one wallet is its identity AND its payout wallet - milestone
// releases land here, and the builder signs from it.
export function companyWallets(username: string): { admin: PrivateKeyAccount } {
  return { admin: deriveAccount("company", username) };
}