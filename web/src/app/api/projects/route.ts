import { NextResponse } from "next/server";
import { prisma } from "@/lib/db";
import { loadProjectSummary } from "@/lib/project";
import { indexProjectsFromChain } from "@/lib/indexer";
import { getSession } from "@/lib/auth";
import { accountFor } from "@/lib/api";
import { publicClient, escrowAt } from "@/lib/chain";

// GET /api/projects - the tender board (chain event index + live lifecycle).
// Rows the viewer is personally involved in (company won it, or they're a
// drawn committee member) are flagged `mine` so the board surfaces them first.
export async function GET() {
  try {
    // The chain is the source of truth for what tenders exist (ProjectCreated
    // events on the factory). If the local cache is empty or the index is
    // behind, rebuild from chain logs - a wiped DB can't lose tenders.
    await indexProjectsFromChain();
    const projects = await prisma.project.findMany({ orderBy: { createdAt: "desc" } });

    const session = await getSession();
    const company =
      session?.role === "company"
        ? await prisma.company.findUnique({ where: { userId: session.userId } })
        : null;
    const memberWallet = session && session.role !== "company" ? accountFor(session).address.toLowerCase() : null;

    const rows = await Promise.all(
      projects.map(async (p) => {
        try {
          const summary = await loadProjectSummary(p.governance as `0x${string}`);
          // Company names for the shortlisted bids come from the DB mirror
          // (the registry stores wallets/hashes, not names).
          const mirror = await prisma.proposal.findMany({
            where: { governance: p.governance, proposalId: { in: summary.shortlist.map(Number) } },
          });
          const nameById = new Map(mirror.map((m) => [String(m.proposalId), m.companyName]));
          const shortlistCompanies = summary.shortlist
            .map((id) => nameById.get(id) ?? null)
            .filter((n): n is string => n !== null);

          // Did the viewer's company win this one, or is the viewer a drawn
          // committee member on it? Only treat it as a win once the tender is
          // actually awarded — before that, winningProposalId is 0 and the
          // 0-based proposal id 0 would falsely match the first bidder.
          let mine = false;
          if (session?.role === "committee") {
            // The committee's "current projects" are the tenders actually in
            // flight: awarded and being worked on.
            mine = summary.lifecycle === "AWARDED";
          } else if (company) {
            const awarded = summary.lifecycle === "AWARDED" || summary.lifecycle === "COMPLETE";
            if (awarded) {
              const winner = await prisma.proposal.findUnique({
                where: {
                  governance_proposalId: {
                    governance: p.governance,
                    proposalId: Number(summary.winningProposalId),
                  },
                },
              });
              mine = winner?.companyName === company.name;
            }
          }
          if (!mine && memberWallet) {
            try {
              const escrowAddr = summary.escrowAddress as `0x${string}`;
              if (escrowAddr && escrowAddr !== "0x0000000000000000000000000000000000000000") {
                const members = (await publicClient.readContract({
                  ...escrowAt(escrowAddr),
                  functionName: "getMemberSigners",
                })) as `0x${string}`[];
                mine = members.some((m) => m.toLowerCase() === memberWallet);
              }
            } catch {
              // project may predate the escrow; leave mine unchanged
            }
          }

          return {
            ...summary,
            shortlistCompanies,
            mine,
            governance: p.governance,
            title: summary.title,
            description: p.description,
            createdAt: p.createdAt,
          };
        } catch {
          return null;
        }
      }),
    );
    return NextResponse.json({ projects: rows.filter(Boolean) });
  } catch {
    return NextResponse.json({ projects: [] });
  }
}