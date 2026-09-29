import { NextResponse } from "next/server";
import { getSession } from "@/lib/auth";
import { prisma } from "@/lib/db";
import { loadProjectSummary } from "@/lib/project";
import { publicClient, redemption, escrowAt } from "@/lib/chain";
import { weiToGES } from "@/lib/config";
import { indexProjectsFromChain } from "@/lib/indexer";

// GET /api/admin/overview - the admin's dashboard headline: active tenders,
// money at a glance, company pulse, and anything that needs action right now.
export async function GET() {
  const session = await getSession();
  if (!session || session.role !== "committee") {
    return NextResponse.json({ error: "Committee role required" }, { status: 403 });
  }
  try {
    await indexProjectsFromChain();
    const projects = await prisma.project.findMany({ orderBy: { createdAt: "desc" } });

    const byLifecycle: Record<string, number> = {};
    const pendingActions: { governance: string; title: string; action: string; label: string }[] = [];
    let totalFunded = BigInt(0);
    let totalReleased = BigInt(0);
    let totalOwed = BigInt(0);

    for (const p of projects) {
      try {
        const summary = await loadProjectSummary(p.governance as `0x${string}`);
        byLifecycle[summary.lifecycle] = (byLifecycle[summary.lifecycle] ?? 0) + 1;

        // Money figures come from the escrow when funded. Read the three
        // numbers directly instead of loading the whole escrow.
        if (summary.lifecycle === "AWARDED" || summary.lifecycle === "COMPLETE") {
          const escrowAddr = summary.escrowAddress as `0x${string}`;
          if (escrowAddr && escrowAddr !== "0x0000000000000000000000000000000000000000") {
            const [budget, reserve, released, owed] = await Promise.all([
              publicClient.readContract({ ...escrowAt(escrowAddr), functionName: "totalProjectBudget" }),
              publicClient.readContract({ ...escrowAt(escrowAddr), functionName: "feeReserve" }),
              publicClient.readContract({ ...escrowAt(escrowAddr), functionName: "totalReleased" }),
              publicClient.readContract({ ...escrowAt(escrowAddr), functionName: "totalUncollectedFees" }),
            ]);
            totalFunded += budget + reserve;
            totalReleased += released;
            totalOwed += owed;
          }
        }

        // What needs the admin's hand right now.
        const now = BigInt(Math.floor(Date.now() / 1000));
        if (summary.lifecycle === "CREATED") {
          pendingActions.push({ governance: p.governance, title: summary.title, action: "acceptProposals", label: "Accept proposals" });
        } else if (summary.lifecycle === "PROPOSAL" && BigInt(summary.proposalDeadline) <= now) {
          pendingActions.push({ governance: p.governance, title: summary.title, action: "openVoting", label: "Open voting" });
        } else if (summary.lifecycle === "VOTING" && BigInt(summary.votingDeadline) <= now) {
          pendingActions.push({ governance: p.governance, title: summary.title, action: "closeVoting", label: "Close voting" });
        } else if (summary.lifecycle === "DELIBERATION" && BigInt(summary.awardDeadline) < now) {
          pendingActions.push({ governance: p.governance, title: summary.title, action: "expire", label: "Expire" });
        }
      } catch {
        // skip broken projects
      }
    }

    const [companyCount, pendingReceipts] = await Promise.all([
      prisma.company.count(),
      publicClient
        .readContract({ ...redemption, functionName: "receiptCount" })
        .then(async (count) => {
          let pending = 0;
          for (let i = 1; i <= Number(count); i++) {
            const r = await publicClient.readContract({
              ...redemption,
              functionName: "receipts",
              args: [BigInt(i)],
            });
            if (Number(r[4]) === 0) pending++;
          }
          return pending;
        })
        .catch(() => 0),
    ]);

    return NextResponse.json({
      tenders: {
        total: projects.length,
        byLifecycle,
      },
      money: {
        funded: weiToGES(totalFunded),
        released: weiToGES(totalReleased),
        owed: weiToGES(totalOwed),
      },
      companies: { registered: companyCount },
      pendingRedemptions: pendingReceipts,
      pendingActions,
    });
  } catch (e) {
    return NextResponse.json({ error: String(e) }, { status: 400 });
  }
}