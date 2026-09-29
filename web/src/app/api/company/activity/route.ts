import { NextResponse } from "next/server";
import { requireUser, companyForUser, apiError } from "@/lib/api";
import { prisma } from "@/lib/db";
import { loadProjectSummary } from "@/lib/project";

// GET /api/company/activity - the company's bids across every tender, with
// live lifecycle and win/lose status from the chain.
export async function GET() {
  const auth = await requireUser();
  if ("error" in auth) return auth.error;
  if (auth.session.role !== "company") {
    return NextResponse.json({ error: "Company role required" }, { status: 403 });
  }
  try {
    const company = await companyForUser(auth.session.userId);
    if (!company) return NextResponse.json({ bids: [] });

    const proposals = await prisma.proposal.findMany({
      where: { companyName: company.name },
      orderBy: { createdAt: "desc" },
    });

    const bids = await Promise.all(
      proposals.map(async (p) => {
        const project = await prisma.project.findUnique({ where: { governance: p.governance } });
        let lifecycle = "UNKNOWN";
        let winningProposalId = "0";
        try {
          const summary = await loadProjectSummary(p.governance as `0x${string}`);
          lifecycle = summary.lifecycle;
          winningProposalId = summary.winningProposalId;
        } catch {
          // project may be on an old chain state; keep placeholders
        }
        return {
          governance: p.governance,
          tenderTitle: project?.title ?? p.governance,
          proposalId: p.proposalId,
          cost: p.cost,
          milestones: JSON.parse(p.milestones) as string[],
          depositRequired: p.depositRequired,
          lifecycle,
          // winningProposalId is 0 until the tender is awarded (ids are
          // 0-based), so only treat a match as a win once it actually is.
          won:
            (lifecycle === "AWARDED" || lifecycle === "COMPLETE") &&
            Number(winningProposalId) === p.proposalId,
        };
      }),
    );

    return NextResponse.json({
      bids,
      totals: {
        submitted: bids.length,
        won: bids.filter((b) => b.won).length,
        inProgress: bids.filter((b) => ["PROPOSAL", "VOTING", "DELIBERATION"].includes(b.lifecycle)).length,
      },
    });
  } catch (e) {
    return apiError(e);
  }
}