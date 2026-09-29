import { NextResponse } from "next/server";
import { encodeFunctionData, type Address } from "viem";
import { requireUser, accountFor, apiError } from "@/lib/api";
import { submit } from "@/lib/relay";
import { governanceAt } from "@/lib/chain";

// POST /api/project/[governance]/vote { proposalId }
export async function POST(req: Request, { params }: { params: Promise<{ governance: string }> }) {
  const auth = await requireUser();
  if ("error" in auth) return auth.error;
  if (auth.session.role === "committee") {
    return NextResponse.json({ error: "The committee cannot vote" }, { status: 403 });
  }
  try {
    const { governance } = await params;
    const { proposalId } = await req.json();
    const data = encodeFunctionData({
      abi: governanceAt(governance as Address).abi,
      functionName: "voteForProposal",
      args: [BigInt(proposalId)],
    });
    const receipt = await submit(accountFor(auth.session), { to: governance as Address, data }, "vote");
    return NextResponse.json({ ok: true, txHash: receipt.hash });
  } catch (e) {
    return apiError(e);
  }
}