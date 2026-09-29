import { NextResponse } from "next/server";
import { encodeFunctionData, type Address } from "viem";
import { requireUser, accountFor, apiError } from "@/lib/api";
import { submit } from "@/lib/relay";
import { governanceAt } from "@/lib/chain";

// POST /api/project/[governance]/optin
export async function POST(_req: Request, { params }: { params: Promise<{ governance: string }> }) {
  const auth = await requireUser();
  if ("error" in auth) return auth.error;
  try {
    const { governance } = await params;
    const data = encodeFunctionData({
      abi: governanceAt(governance as Address).abi,
      functionName: "optInForCommittee",
    });
    const receipt = await submit(accountFor(auth.session), { to: governance as Address, data }, "optin");
    return NextResponse.json({ ok: true, txHash: receipt.hash });
  } catch (e) {
    return apiError(e);
  }
}