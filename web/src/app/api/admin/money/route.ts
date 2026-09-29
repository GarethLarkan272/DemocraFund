import { NextResponse } from "next/server";
import { getSession } from "@/lib/auth";
import { prisma } from "@/lib/db";
import { loadProject, feeCredit } from "@/lib/project";
import { escrowAt, publicClient } from "@/lib/chain";
import { indexProjectsFromChain } from "@/lib/indexer";

type TenderRow = {
  governance: string;
  title: string;
  lifecycle: string;
  address: string;
  totalProjectBudget: string;
  feeReserve: string;
  totalReleased: string;
  settlementPaid: string;
  feesCollected: string;
  totalUncollectedFees: string;
  totalReturnedOnCancellation: string;
  totalSweptToTreasury: string;
  balance: string;
  milestonesReleased: number;
  milestonesTotal: number;
};

// GET /api/admin/money - the club's money overview: every tender's funded,
// released, fee, and treasury numbers plus a leaderboard of fee earners.
export async function GET() {
  const session = await getSession();
  if (!session || session.role !== "committee") {
    return NextResponse.json({ error: "Committee role required" }, { status: 403 });
  }
  try {
    await indexProjectsFromChain();
    const projects = await prisma.project.findMany({ orderBy: { createdAt: "desc" } });

    const tenders: (TenderRow | null)[] = await Promise.all(
      projects.map(async (p) => {
        try {
          const full = await loadProject(p.governance as `0x${string}`);
          if (!full.escrow) return null;
          const e = full.escrow;
          return {
            governance: p.governance,
            title: full.title,
            lifecycle: full.lifecycle,
            address: full.address,
            totalProjectBudget: e.totalProjectBudget,
            feeReserve: e.feeReserve,
            totalReleased: e.totalReleased,
            settlementPaid: e.settlementPaid,
            feesCollected: e.feesCollected,
            totalUncollectedFees: e.totalUncollectedFees,
            totalReturnedOnCancellation: e.totalReturnedOnCancellation,
            totalSweptToTreasury: e.totalSweptToTreasury,
            balance: e.balance,
            milestonesReleased: e.milestones.filter((m) => m.released).length,
            milestonesTotal: e.milestones.length,
          };
        } catch {
          return null;
        }
      }),
    );
    const funded = tenders.filter((t) => t !== null) as TenderRow[];

    // Fee leaderboard: every drawn committee member across all escrows, with
    // their total fee credits (earned, incl. already collected).
    const leaderboard = new Map<string, bigint>();
    for (const p of projects) {
      try {
        const full = await loadProject(p.governance as `0x${string}`);
        if (!full.escrow) continue;
        const escrow = escrowAt(full.escrow.address as `0x${string}`);
        const members = (await publicClient.readContract({
          ...escrow,
          functionName: "getMemberSigners",
        })) as `0x${string}`[];
        for (const m of members) {
          const c = await feeCredit(full.escrow.address as `0x${string}`, m);
          leaderboard.set(m.toLowerCase(), (leaderboard.get(m.toLowerCase()) ?? BigInt(0)) + BigInt(c));
        }
      } catch {
        // skip broken projects
      }
    }

    const sum = (k: keyof TenderRow) =>
      funded.reduce((s, t) => s + Number(t[k]), 0);

    return NextResponse.json({
      tenders: funded,
      totals: {
        tenders: funded.length,
        funded: sum("totalProjectBudget") + sum("feeReserve"),
        released: sum("totalReleased"),
        feesCollected: sum("feesCollected"),
        feesOwed: sum("totalUncollectedFees"),
        settlementPaid: sum("settlementPaid"),
        returned: sum("totalReturnedOnCancellation"),
        swept: sum("totalSweptToTreasury"),
        balance: sum("balance"),
      },
      leaderboard: [...leaderboard.entries()]
        .map(([wallet, credits]) => ({ wallet, credits: credits.toString() }))
        .sort((a, b) => Number(b.credits) - Number(a.credits)),
    });
  } catch (e) {
    return NextResponse.json({ error: String(e) }, { status: 400 });
  }
}