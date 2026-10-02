import { type Address } from "viem";
import { projectFactory, publicClient, governanceAt } from "./chain";
import { prisma } from "./db";
import { loadProjectSummary } from "./project";
import { weiToGES } from "./config";

const PROJECT_CREATED_EVENT = {
  type: "event",
  name: "ProjectCreated",
  inputs: [
    { type: "address", name: "projectInstance", indexed: true, internalType: "address" },
  ],
} as const;

// The factory does not store a project list - only projectCount + an isProject
// mapping. The authoritative enumeration is the ProjectCreated event stream,
// which the chain keeps forever. The DB is just a fast cache of it: after a
// wipe, the board rebuilds itself from logs. Returns the number of projects
// found (before dedup).
export async function indexProjectsFromChain(): Promise<number> {
  const latest = await publicClient.getBlockNumber();

  let from: bigint;
  const state = await prisma.indexState.findUnique({ where: { id: 1 } });
  if (state) {
    from = state.lastBlock + BigInt(1);
  } else {
    // First index: scan from the chain's beginning. eth_getLogs over a huge
    // range works on this RPC; new projects are appended incrementally.
    from = BigInt(0);
  }

  if (from > latest) return 0;

  // Backfill the escrow address for every known project so redemption
  // receipts can be attributed to the project that paid the redeemer. The
  // escrow is created at award time (0x0 before that). Only runs when the
  // index advanced - polls with no new blocks skip it.
  const projects = await prisma.project.findMany();
  for (const p of projects) {
    if (p.escrowAddress) continue;
    try {
      const escrow = await publicClient.readContract({
        ...governanceAt(p.governance as Address),
        functionName: "projectEscrow",
      });
      if (escrow !== "0x0000000000000000000000000000000000000000") {
        await prisma.project.update({
          where: { governance: p.governance },
          data: { escrowAddress: escrow.toLowerCase() },
        });
      }
    } catch {
      // project predates the escrow getter; leave unset
    }
  }

  const CHUNK = BigInt(5000000);
  let found = 0;
  for (let start = from; start <= latest; start += CHUNK) {
    const end = start + CHUNK - BigInt(1) > latest ? latest : start + CHUNK - BigInt(1);
    const logs = await publicClient.getLogs({
      address: projectFactory.address,
      event: PROJECT_CREATED_EVENT,
      fromBlock: start,
      toBlock: end,
    });
    for (const log of logs) {
      const governance = log.args.projectInstance?.toLowerCase() as Address;
      if (!governance) continue;
      const existing = await prisma.project.findUnique({ where: { governance } });
      if (existing) continue;
      found++;

      let title = "Untitled tender";
      let department = "";
      let category = "";
      try {
        const summary = await loadProjectSummary(governance);
        title = summary.title;
        department = summary.department;
        category = summary.category;
      } catch {
        // governance readable; leave placeholders
      }

      await prisma.project.create({
        data: {
          governance,
          factory: projectFactory.address.toLowerCase(),
          title,
          department,
          category,
          ipfsHash: "0x",
        },
      });
    }
  }

  await prisma.indexState.upsert({
    where: { id: 1 },
    update: { lastBlock: latest },
    create: { id: 1, lastBlock: latest },
  });

  await indexProposalsFromChain();

  return found;
}

// The Proposal table is a mirror of on-chain bids (the chain is the source of
// truth). It is wiped and rebuilt like the project index, so a fresh DB still
// shows every company's bids, wins, and costs. The milestone breakdown is not
// recoverable from the chain (solc omits dynamic arrays from the struct
// getter), so it stays empty after a wipe.
async function indexProposalsFromChain() {
  const [projects, companies] = await Promise.all([
    prisma.project.findMany(),
    prisma.company.findMany(),
  ]);
  const companyNameByWallet = new Map(
    companies.map((c) => [c.adminWallet.toLowerCase(), c.name]),
  );

  for (const p of projects) {
    try {
      const count = Number(
        await publicClient.readContract({
          ...governanceAt(p.governance as Address),
          functionName: "numberOfProposals",
        }),
      );
      for (let i = 0; i < count; i++) {
        const proposal = await publicClient.readContract({
          ...governanceAt(p.governance as Address),
          functionName: "proposals",
          args: [BigInt(i)],
        });
        const adminWallet = (proposal[2] as string).toLowerCase();
        const companyName = companyNameByWallet.get(adminWallet) ?? null;
        if (!companyName) continue;

        const existing = await prisma.proposal.findUnique({
          where: {
            governance_proposalId: { governance: p.governance, proposalId: i },
          },
        });
        if (existing) {
          await prisma.proposal.update({
            where: { governance_proposalId: { governance: p.governance, proposalId: i } },
            data: {
              companyName,
              cost: weiToGES(proposal[1]),
              milestones: "[]",
              specContentHash: proposal[3] as string,
              ipfsHash: proposal[4] as string,
              depositRequired: proposal[5] as boolean,
            },
          });
        } else {
          await prisma.proposal.create({
            data: {
              proposalId: i,
              companyName,
              cost: weiToGES(proposal[1]),
              milestones: "[]",
              specContentHash: proposal[3] as string,
              ipfsHash: proposal[4] as string,
              depositRequired: proposal[5] as boolean,
              project: { connect: { governance: p.governance } },
            },
          });
        }
      }
    } catch {
      // project predates the proposals getter; skip
    }
  }
}