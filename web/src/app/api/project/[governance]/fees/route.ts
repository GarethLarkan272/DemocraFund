import { NextResponse } from "next/server";
import { encodeFunctionData, type Address } from "viem";
import { requireUser, accountFor, apiError } from "@/lib/api";
import { submit } from "@/lib/relay";
import { escrowAt, governanceAt, publicClient } from "@/lib/chain";

// POST /api/project/[governance]/fees  -> collectFees() for the caller's wallet
export async function POST(_req: Request, { params }: { params: Promise<{ governance: string }> }) {
  const auth = await requireUser();
  if ("error" in auth) return auth.error;
  try {
    const { governance } = await params;
    const escrowAddr = (await publicClient.readContract({
      ...governanceAt(governance as Address),
      functionName: "projectEscrow",
    })) as Address;
    const data = encodeFunctionData({
      abi: escrowAt(escrowAddr).abi,
      functionName: "collectFees",
    });
    const receipt = await submit(accountFor(auth.session), { to: escrowAddr, data }, "collectFees");
    return NextResponse.json({ ok: true, txHash: receipt.hash });
  } catch (e) {
    return apiError(e);
  }
}