import { NextResponse } from "next/server";
import { getSession } from "./auth";
import { prisma } from "./db";
import { deriveAccount, deriveRoleWallet } from "./wallets";
import type { PrivateKeyAccount } from "viem/accounts";
import { friendlyError } from "./errors";

export async function requireUser() {
  const session = await getSession();
  if (!session) {
    return { error: NextResponse.json({ error: "Not logged in" }, { status: 401 }) };
  }
  return { session };
}

// The custodial account behind a session: members/companies derive from their
// username; the committee is the fixed role wallet (one on-chain identity).
export function accountFor(session: { username: string; role: string }): PrivateKeyAccount {
  if (session.role === "committee") return deriveRoleWallet("committee");
  return deriveAccount(session.role, session.username);
}

export async function companyForUser(userId: number) {
  return prisma.company.findUnique({ where: { userId } });
}

// Returns a friendly, human message for on-chain reverts; falls back to the
// raw message when the reason isn't in our map.
export async function apiError(e: unknown, fallback = "Something went wrong") {
  console.error(e);
  const friendly = await friendlyError(e);
  if (friendly) return NextResponse.json({ error: friendly }, { status: 400 });
  const message = e instanceof Error ? e.message : fallback;
  return NextResponse.json({ error: message }, { status: 400 });
}