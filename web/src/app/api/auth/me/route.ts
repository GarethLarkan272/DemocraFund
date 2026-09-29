import { NextResponse } from "next/server";
import { destroySession, getSession } from "@/lib/auth";
import { deriveAccount, deriveRoleWallet } from "@/lib/wallets";

export async function GET() {
  const session = await getSession();
  if (!session) return NextResponse.json({ user: null });

  const account = session.role === "committee"
    ? deriveRoleWallet("committee")
    : deriveAccount(session.role, session.username);

  return NextResponse.json({
    user: { username: session.username, role: session.role },
    wallet: account.address,
  });
}

export async function POST() {
  await destroySession();
  return NextResponse.json({ ok: true });
}