import { NextResponse } from "next/server";
import { getSession } from "@/lib/auth";
import { prisma } from "@/lib/db";
import { companyRegistry, publicClient } from "@/lib/chain";
import { loadProjectSummary } from "@/lib/project";
import { indexProjectsFromChain } from "@/lib/indexer";

// GET /api/admin/companies - the registry pulse: counts + per-company
// activity (bids submitted, tenders won) with live on-chain active state.
export async function GET() {
  const session = await getSession();
  if (!session || session.role !== "committee") {
    return NextResponse.json({ error: "Committee role required" }, { status: 403 });
  }
  try {
    await indexProjectsFromChain();
    const [companies, projects] = await Promise.all([
      prisma.company.findMany({ orderBy: { onChainId: "asc" } }),
      prisma.project.findMany(),
    ]);

    // Wins: for each project with a winner, resolve the company name from the
    // proposal mirror (the registry stores wallets, not names). winningProposalId
    // is 0-based, so proposal 0 is a legitimate winner - only ignore it when
    // the tender was never awarded (the id is 0 AND not yet awarded).
    const winsByCompany = new Map<string, number>();
    for (const p of projects) {
      try {
        const summary = await loadProjectSummary(p.governance as `0x${string}`);
        const awarded = summary.lifecycle === "AWARDED" || summary.lifecycle === "COMPLETE";
        if (!awarded) continue;
        const winnerId = Number(summary.winningProposalId);
        const mirror = await prisma.proposal.findUnique({
          where: { governance_proposalId: { governance: p.governance, proposalId: winnerId } },
        });
        if (mirror) {
          winsByCompany.set(mirror.companyName, (winsByCompany.get(mirror.companyName) ?? 0) + 1);
        }
      } catch {
        // skip broken projects
      }
    }

    // Bids per company from the proposal mirror.
    const bids = await prisma.proposal.groupBy({
      by: ["companyName"],
      _count: { _all: true },
    });
    const bidsByCompany = new Map(bids.map((b) => [b.companyName, b._count._all]));

    // Live active state from the registry.
    const rows = await Promise.all(
      companies.map(async (c) => {
        let active = c.active;
        try {
          const chain = await publicClient.readContract({
            ...companyRegistry,
            functionName: "companies",
            args: [BigInt(c.onChainId)],
          });
          active = chain[2];
        } catch {
          // fall back to the mirror
        }
        return {
          name: c.name,
          onChainId: c.onChainId,
          adminWallet: c.adminWallet,
          active,
          bids: bidsByCompany.get(c.name) ?? 0,
          wins: winsByCompany.get(c.name) ?? 0,
        };
      }),
    );

    return NextResponse.json({
      companies: rows,
      totals: {
        registered: rows.length,
        active: rows.filter((r) => r.active).length,
        bidding: rows.filter((r) => r.bids > 0).length,
      },
    });
  } catch (e) {
    return NextResponse.json({ error: String(e) }, { status: 400 });
  }
}