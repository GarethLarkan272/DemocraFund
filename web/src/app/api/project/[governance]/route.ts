import { NextResponse } from "next/server";
import type { Address } from "viem";
import { loadProject, optedIn, hasVoted, hasSignedMilestone } from "@/lib/project";
import { getSession } from "@/lib/auth";
import { accountFor } from "@/lib/api";
import { prisma } from "@/lib/db";
import { deriveAccount } from "@/lib/wallets";
import { escrowAt, publicClient } from "@/lib/chain";

// How many of the milestone's signers have signed (admin + builder + members).
async function signatureCount(escrow: Address, milestoneCount: number): Promise<number[]> {
  const e = escrowAt(escrow);
  const [admin, builder, members] = await Promise.all([
    publicClient.readContract({ ...e, functionName: "adminSigner" }),
    publicClient.readContract({ ...e, functionName: "builderSigner" }),
    publicClient.readContract({ ...e, functionName: "getMemberSigners" }),
  ]);
  const signers = [admin, builder, ...(members as Address[])];
  return Promise.all(
    Array.from({ length: milestoneCount }, (_, i) =>
      (async () => {
        let n = 0;
        for (const s of signers) {
          if (await hasSignedMilestone(escrow, i, s as Address)) n++;
        }
        return n;
      })(),
    ),
  );
}

// GET /api/project/[governance] - full live state of a tender
export async function GET(_req: Request, { params }: { params: Promise<{ governance: string }> }) {
  try {
    const { governance } = await params;
    const project = await loadProject(governance as Address);
    const row = await prisma.project.findUnique({ where: { governance: governance.toLowerCase() } });
    let sigCounts: number[] = [];
    if (project.escrow) {
      sigCounts = await signatureCount(
        project.escrow.address as Address,
        project.escrow.milestones.length,
      );
    }
    const session = await getSession();
    let meOptedIn = false;
    let meVoted = false;
    let meSigned: boolean[] = [];
    if (session) {
      const voter = accountFor(session).address;
      meOptedIn = await optedIn(governance as Address, voter);
      meVoted = await hasVoted(governance as Address, voter);
      if (project.escrow) {
        meSigned = await Promise.all(
          project.escrow.milestones.map((_, i) =>
            hasSignedMilestone(project.escrow!.address as Address, i, voter),
          ),
        );
      }
    }

    // Name the drawn committee members: their wallets are derived from
    // username, so map member accounts back to usernames for display.
    // Members can live in the governance array (VRF draw) or only in the
    // escrow (small pool, everyone serves) - cover both.
    const memberUsers = await prisma.user.findMany({ where: { role: "member" } });
    const nameByWallet = new Map<string, string>();
    for (const u of memberUsers) {
      nameByWallet.set(deriveAccount("member", u.username).address.toLowerCase(), u.username);
    }
    const drawn = [
      ...project.committeeMembers,
      ...project.alternates,
      ...(project.escrow?.memberSigners ?? []),
      ...(project.escrow?.alternates ?? []),
    ];
    const memberNames = Object.fromEntries(
      drawn.map((m) => [m.toLowerCase(), nameByWallet.get(m.toLowerCase()) ?? null]),
    );

    return NextResponse.json({
      project: { ...project, description: row?.description ?? null },
      memberNames,
      meOptedIn,
      meVoted,
      meSigned,
      sigCounts,
    });
  } catch (e) {
    return NextResponse.json({ error: String(e) }, { status: 400 });
  }
}