import { NextResponse } from "next/server";
import { encodeFunctionData, type Address } from "viem";
import { requireUser, accountFor, apiError } from "@/lib/api";
import { submit } from "@/lib/relay";
import { escrowAt, governanceAt, publicClient } from "@/lib/chain";
import { prisma } from "@/lib/db";
import { loadProjectSummary } from "@/lib/project";
import { weiToGES } from "@/lib/config";

// GET /api/fees - every committee fee credit owed to the caller across all
// escrows they're a member of, plus a collect button per tender.
export async function GET() {
  const auth = await requireUser();
  if ("error" in auth) return auth.error;
  try {
    const wallet = accountFor(auth.session).address.toLowerCase();
    const projects = await prisma.project.findMany({ orderBy: { createdAt: "desc" } });

    const tenders: { governance: string; title: string; owed: string }[] = [];
    let totalOwed = 0;
    for (const p of projects) {
      try {
        const summary = await loadProjectSummary(p.governance as `0x${string}`);
        const escrowAddr = summary.escrowAddress as Address;
        if (escrowAddr === "0x0000000000000000000000000000000000000000") continue;
        const owed = await publicClient.readContract({
          ...escrowAt(escrowAddr),
          functionName: "feeCredits",
          args: [wallet as Address],
        });
        if (Number(owed) > 0) {
          tenders.push({ governance: p.governance, title: summary.title, owed: weiToGES(owed) });
          totalOwed += Number(owed);
        }
      } catch {
        // skip broken projects
      }
    }
    return NextResponse.json({ tenders, totalOwed: weiToGES(BigInt(totalOwed)) });
  } catch (e) {
    return apiError(e);
  }
}

// POST /api/fees - collect the caller's fees from one escrow.
export async function POST(req: Request) {
  const auth = await requireUser();
  if ("error" in auth) return auth.error;
  try {
    const { governance } = await req.json();
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