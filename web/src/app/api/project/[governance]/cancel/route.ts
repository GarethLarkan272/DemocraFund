import { NextResponse } from "next/server";
import { keccak256, encodeFunctionData, type Address } from "viem";
import { requireUser, accountFor, apiError } from "@/lib/api";
import { submit } from "@/lib/relay";
import { escrowAt, governanceAt, publicClient } from "@/lib/chain";
import { companyWallets } from "@/lib/wallets";
import { cancellationSigs } from "@/lib/eip712";

// POST /api/project/[governance]/cancel { reason }
// The caller (a signer) commits to the shared cancellation reasonHash.
export async function POST(req: Request, { params }: { params: Promise<{ governance: string }> }) {
  const auth = await requireUser();
  if ("error" in auth) return auth.error;

  try {
    const { governance } = await params;
    const { reason } = await req.json();
    if (!reason) return NextResponse.json({ error: "A cancellation reason is required" }, { status: 400 });
    const reasonHash = keccak256(Buffer.from(String(reason)));

    const escrowAddr = (await publicClient.readContract({
      ...governanceAt(governance as Address),
      functionName: "projectEscrow",
    })) as Address;

    const account =
      auth.session.role === "company"
        ? companyWallets(auth.session.username).admin
        : accountFor(auth.session);

    const sig = await cancellationSigs(account, escrowAddr, reasonHash);
    const data = encodeFunctionData({
      abi: escrowAt(escrowAddr).abi,
      functionName: "approveCancellation",
      args: [reasonHash, [sig]],
    });
    const receipt = await submit(account, { to: escrowAddr, data }, "approveCancellation");
    return NextResponse.json({ ok: true, txHash: receipt.hash, reasonHash });
  } catch (e) {
    return apiError(e);
  }
}