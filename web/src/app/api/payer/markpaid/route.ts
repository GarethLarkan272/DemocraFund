import { NextResponse } from "next/server";
import { encodeFunctionData } from "viem";
import { getSession } from "@/lib/auth";
import { apiError } from "@/lib/api";
import { submit } from "@/lib/relay";
import { redemption } from "@/lib/chain";
import { deriveRoleWallet } from "@/lib/wallets";

// POST /api/payer/markpaid { tokenId, payoutRef }
// The paying authority (PAYER_ROLE wallet) certifies the fiat payout on-chain.
export async function POST(req: Request) {
  const session = await getSession();
  if (!session || session.role !== "payer") {
    return NextResponse.json({ error: "Payer role required" }, { status: 403 });
  }
  try {
    const { tokenId, payoutRef } = await req.json();
    const data = encodeFunctionData({
      abi: redemption.abi,
      functionName: "markPaid",
      args: [BigInt(tokenId), String(payoutRef)],
    });
    const receipt = await submit(deriveRoleWallet("payer"), { to: redemption.address, data }, "markPaid");
    return NextResponse.json({ ok: true, txHash: receipt.hash });
  } catch (e) {
    return apiError(e);
  }
}