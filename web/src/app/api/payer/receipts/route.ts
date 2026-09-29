import { NextResponse } from "next/server";
import { getSession } from "@/lib/auth";
import { apiError } from "@/lib/api";
import { redemption, publicClient } from "@/lib/chain";
import { weiToGES } from "@/lib/config";
import { prisma } from "@/lib/db";

// GET /api/payer/receipts - every redemption receipt with live on-chain state.
// The receipt NFT stores addresses only; the app resolves them to the
// redeemer's company name and the provenance tender's title for display.
export async function GET() {
  const session = await getSession();
  if (!session || session.role !== "payer") {
    return NextResponse.json({ error: "Payer role required" }, { status: 403 });
  }
  try {
    const count = Number(
      await publicClient.readContract({ ...redemption, functionName: "receiptCount" }),
    );
    const [companies, projects] = await Promise.all([
      prisma.company.findMany(),
      prisma.project.findMany(),
    ]);
    const companyByWallet = new Map(companies.map((c) => [c.adminWallet.toLowerCase(), c.name]));
    const projectByEscrow = new Map(
      projects.filter((p) => p.escrowAddress).map((p) => [p.escrowAddress!.toLowerCase(), p]),
    );

    const receipts = await Promise.all(
      Array.from({ length: count }, async (_, i) => {
        const r = await publicClient.readContract({
          ...redemption,
          functionName: "receipts",
          args: [BigInt(i + 1)],
        });
        const redeemer = r[0].toLowerCase();
        const escrow = r[1].toLowerCase();
        const project = projectByEscrow.get(escrow);
        return {
          tokenId: String(i + 1),
          redeemer,
          redeemerName: companyByWallet.get(redeemer) ?? shortWallet(r[0]),
          escrow,
          projectName: project?.title ?? shortWallet(r[1]),
          governance: project?.governance ?? null,
          amount: weiToGES(r[2]),
          destinationId: r[3],
          state: ["Pending", "Paid", "Rejected"][Number(r[4])],
          payoutRef: r[5],
        };
      }),
    );
    return NextResponse.json({ receipts: receipts.reverse() });
  } catch (e) {
    return apiError(e);
  }
}

function shortWallet(a: string) {
  return `${a.slice(0, 6)}…${a.slice(-4)}`;
}