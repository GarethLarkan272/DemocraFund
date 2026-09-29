import { decodeAbiParameters, type Address, type Hex } from "viem";
import { publicClient, governanceAt, escrowAt, paymentToken } from "./chain";
import { prisma } from "./db";

export function bytes32ToString(b: Hex): string {
  const decoded = decodeAbiParameters([{ type: "bytes32" }], b)[0] as Hex;
  return Buffer.from(decoded.slice(2), "hex").toString("utf8").replace(/\0+$/, "");
}

// GES is an 18-decimal ERC-20. Every API response exposes human-readable GES
// amounts (wei / 1e18) so the UI never divides. Rounds to 6 decimals so
// wei-dust from legacy conversions never shows as 4999.999999999999958.
export function weiToGES(v: bigint | string | number): string {
  const wei = BigInt(v);
  const scaled = (Number(wei) / 10 ** 18).toFixed(6);
  return String(Number(scaled));
}

const LIFECYCLE = ["CREATED", "PROPOSAL", "VOTING", "DELIBERATION", "AWARDED", "COMPLETE", "CANCELLED"];

// Short-lived cache for the summary: the board polls every 8s and admin
// routes re-read summaries repeatedly. Lifecycle state only changes on
// explicit transactions, so a 15s TTL is safe and cuts RPC round-trips.
const summaryCache = new Map<string, { at: number; data: Awaited<ReturnType<typeof loadProjectSummaryInner>> }>();
const SUMMARY_TTL_MS = 15_000;

async function loadProjectSummaryInner(governance: Address) {
  const g = governanceAt(governance);
  const [
    lifecycle,
    title,
    department,
    category,
    budgetCap,
    proposalDeadline,
    votingDeadline,
    deliberationWindow,
    awardDeadline,
    numberOfProposals,
    projectEscrow,
    shortlistCount,
    numberOfShortlistedProjects,
  ] = await Promise.all([
      publicClient.readContract({ ...g, functionName: "projectLifecycle" }),
      publicClient.readContract({ ...g, functionName: "title" }),
      publicClient.readContract({ ...g, functionName: "department" }),
      publicClient.readContract({ ...g, functionName: "category" }),
      publicClient.readContract({ ...g, functionName: "budgetCap" }),
      publicClient.readContract({ ...g, functionName: "proposalDeadline" }),
      publicClient.readContract({ ...g, functionName: "votingDeadline" }),
      publicClient.readContract({ ...g, functionName: "deliberationWindow" }),
      publicClient.readContract({ ...g, functionName: "awardDeadline" }),
      publicClient.readContract({ ...g, functionName: "numberOfProposals" }),
      publicClient.readContract({ ...g, functionName: "projectEscrow" }),
      publicClient.readContract({ ...g, functionName: "shortlistCount" }),
      publicClient.readContract({ ...g, functionName: "numberOfShortlistedProjects" }),
    ]);
  const winningProposalId = await publicClient.readContract({
    ...g,
    functionName: "winningProposalId",
  });

  // Shortlist is committed on-chain at closeVoting (top-N by votes, ties pass).
  const shortlist: string[] = [];
  for (let i = 0; i < Number(shortlistCount); i++) {
    try {
      shortlist.push(
        (
          (await publicClient.readContract({
            ...g,
            functionName: "shortlistProposalIds",
            args: [BigInt(i)],
          })) as bigint
        ).toString(),
      );
    } catch {
      break;
    }
  }

  return {
    lifecycle: LIFECYCLE[Number(lifecycle)],
    title: bytes32ToString(title),
    department: bytes32ToString(department),
    category: bytes32ToString(category),
    budgetCap: weiToGES(budgetCap),
    proposalDeadline: proposalDeadline.toString(),
    votingDeadline: votingDeadline.toString(),
    deliberationWindow: deliberationWindow.toString(),
    awardDeadline: awardDeadline.toString(),
    numberOfProposals: numberOfProposals.toString(),
    numberOfShortlistedProjects: numberOfShortlistedProjects.toString(),
    winningProposalId: winningProposalId.toString(),
    shortlist,
    escrowAddress: projectEscrow,
  };
}

export async function loadProjectSummary(governance: Address) {
  const cached = summaryCache.get(governance.toLowerCase());
  if (cached && Date.now() - cached.at < SUMMARY_TTL_MS) return cached.data;
  const data = await loadProjectSummaryInner(governance);
  summaryCache.set(governance.toLowerCase(), { at: Date.now(), data });
  return data;
}

export async function loadProject(governance: Address) {
  const g = governanceAt(governance);
  const [
    lifecycle,
    title,
    category,
    department,
    budgetCap,
    committeeFeePerSignature,
    proposalDeadline,
    votingDeadline,
    awardDeadline,
    deliberationWindow,
    numberOfProposals,
    numberOfShortlistedProjects,
    numberOfTotalMilestones,
    winningProposalId,
    projectEscrow,
    treasuryWallet,
    safeWallet,
    token,
    factory,
    registry,
    optedInCount,
    selectionPending,
    selectionRequestId,
    selectionRequestedAt,
    cancelledForm,
    ipfsHash,
  ] = await Promise.all([
    publicClient.readContract({ ...g, functionName: "projectLifecycle" }),
    publicClient.readContract({ ...g, functionName: "title" }),
    publicClient.readContract({ ...g, functionName: "category" }),
    publicClient.readContract({ ...g, functionName: "department" }),
    publicClient.readContract({ ...g, functionName: "budgetCap" }),
    publicClient.readContract({ ...g, functionName: "committeeFeePerSignature" }),
    publicClient.readContract({ ...g, functionName: "proposalDeadline" }),
    publicClient.readContract({ ...g, functionName: "votingDeadline" }),
    publicClient.readContract({ ...g, functionName: "awardDeadline" }),
    publicClient.readContract({ ...g, functionName: "deliberationWindow" }),
    publicClient.readContract({ ...g, functionName: "numberOfProposals" }),
    publicClient.readContract({ ...g, functionName: "numberOfShortlistedProjects" }),
    publicClient.readContract({ ...g, functionName: "numberOfTotalMilestones" }),
    publicClient.readContract({ ...g, functionName: "winningProposalId" }),
    publicClient.readContract({ ...g, functionName: "projectEscrow" }),
    publicClient.readContract({ ...g, functionName: "treasuryWallet" }),
    publicClient.readContract({ ...g, functionName: "projectGovernanceSafeWallet" }),
    publicClient.readContract({ ...g, functionName: "token" }),
    publicClient.readContract({ ...g, functionName: "projectFactory" }),
    publicClient.readContract({ ...g, functionName: "companyRegistry" }),
    publicClient.readContract({ ...g, functionName: "optInCount" }),
    publicClient.readContract({ ...g, functionName: "selectionPending" }),
    publicClient.readContract({ ...g, functionName: "selectionRequestId" }),
    publicClient.readContract({ ...g, functionName: "selectionRequestedAt" }),
    publicClient.readContract({ ...g, functionName: "cancelledForm" }),
    publicClient.readContract({ ...g, functionName: "ipfsHash" }),
  ]);

  // Public arrays only expose per-index getters AND revert when out of bounds -
  // probe indices until one reverts.
  async function readArray(fn: "committeeMembers" | "alternates", limit: number) {
    const out: Address[] = [];
    for (let i = 0; i < limit; i++) {
      try {
        out.push(
          (await publicClient.readContract({ ...g, functionName: fn, args: [BigInt(i)] })) as Address,
        );
      } catch {
        break;
      }
    }
    return out;
  }
  const [committeeMembers, alternates, shortlistCount] = await Promise.all([
    readArray("committeeMembers", 3),
    readArray("alternates", 2),
    publicClient.readContract({ ...g, functionName: "shortlistCount" }),
  ]);

  // Shortlist is committed on-chain at closeVoting (top-N by votes, ties pass).
  const shortlist: string[] = [];
  for (let i = 0; i < Number(shortlistCount); i++) {
    try {
      shortlist.push(
        (
          (await publicClient.readContract({
            ...g,
            functionName: "shortlistProposalIds",
            args: [BigInt(i)],
          })) as bigint
        ).toString(),
      );
    } catch {
      break;
    }
  }

  // createProposal stores at proposals[numberOfProposals] then increments, so
// the first proposal has id 0 - ids are 0-based.
  const proposalIds = Array.from({ length: Number(numberOfProposals) }, (_, i) => BigInt(i));

  // The on-chain getter flattens the Proposal struct WITHOUT the dynamic
  // milestones array (documented solc getter quirk) - mirror data from the DB.
  const dbProposals = await prisma.proposal.findMany({
    where: { governance: governance.toLowerCase() },
  });
  const dbByProposalId = new Map(dbProposals.map((p) => [p.proposalId, p]));

  const proposals = await Promise.all(
    proposalIds.map(async (id) => {
      const p = await publicClient.readContract({ ...g, functionName: "proposals", args: [id] });
      const votes = await publicClient.readContract({
        ...g,
        functionName: "numberOfVotesPerProposal",
        args: [id],
      });
      const mirror = dbByProposalId.get(Number(id));
      return {
        id: p[0].toString(),
        cost: weiToGES(p[1]),
        admin: p[2],
        fundWallet: p[3],
        specContentHash: p[4],
        ipfsHash: p[5],
        depositRequired: p[6],
        companyName: mirror?.companyName ?? null,
        milestones: mirror ? (JSON.parse(mirror.milestones) as string[]) : [],
        votes: votes.toString(),
      };
    }),
  );

  const escrow =
    projectEscrow === "0x0000000000000000000000000000000000000000"
      ? null
      : await loadEscrow(projectEscrow as Address, Number(numberOfTotalMilestones));

  return {
    address: governance,
    lifecycle: LIFECYCLE[Number(lifecycle)],
    cancelledForm: LIFECYCLE[Number(cancelledForm)],
    title: bytes32ToString(title),
    category: bytes32ToString(category),
    department: bytes32ToString(department),
    ipfsHash,
    budgetCap: weiToGES(budgetCap),
    committeeFeePerSignature: weiToGES(committeeFeePerSignature),
    proposalDeadline: proposalDeadline.toString(),
    votingDeadline: votingDeadline.toString(),
    awardDeadline: awardDeadline.toString(),
    deliberationWindow: deliberationWindow.toString(),
    numberOfProposals: numberOfProposals.toString(),
    numberOfShortlistedProjects: numberOfShortlistedProjects.toString(),
    winningProposalId: winningProposalId.toString(),
    treasuryWallet,
    safeWallet,
    token,
    factory,
    registry,
    optedInCount: optedInCount.toString(),
    selectionPending,
    selectionRequestId: selectionRequestId.toString(),
    selectionRequestedAt: selectionRequestedAt.toString(),
    committeeMembers,
    alternates,
    shortlist,
    proposals,
    escrow,
  };
}

export async function loadEscrow(escrow: Address, milestoneCount: number) {
  const e = escrowAt(escrow);
  const [
    totalProjectBudget,
    feeReserve,
    totalReleased,
    settlementPaid,
    totalReturnedOnCancellation,
    totalSweptToTreasury,
    feesCollected,
    totalUncollectedFees,
    currentMilestoneIndex,
    cancelled,
    committeeFinalized,
    treasuryWallet,
    builderSigner,
    memberSigners,
    alternates,
  ] = await Promise.all([
    publicClient.readContract({ ...e, functionName: "totalProjectBudget" }),
    publicClient.readContract({ ...e, functionName: "feeReserve" }),
    publicClient.readContract({ ...e, functionName: "totalReleased" }),
    publicClient.readContract({ ...e, functionName: "settlementPaid" }),
    publicClient.readContract({ ...e, functionName: "totalReturnedOnCancellation" }),
    publicClient.readContract({ ...e, functionName: "totalSweptToTreasury" }),
    publicClient.readContract({ ...e, functionName: "feesCollected" }),
    publicClient.readContract({ ...e, functionName: "totalUncollectedFees" }),
    publicClient.readContract({ ...e, functionName: "currentMilestoneIndex" }),
    publicClient.readContract({ ...e, functionName: "cancelled" }),
    publicClient.readContract({ ...e, functionName: "committeeFinalized" }),
    publicClient.readContract({ ...e, functionName: "treasuryWallet" }),
    publicClient.readContract({ ...e, functionName: "builderSigner" }),
    publicClient.readContract({ ...e, functionName: "getMemberSigners" }),
    publicClient.readContract({ ...e, functionName: "getAlternates" }),
  ]);

  const milestones = await Promise.all(
    Array.from({ length: Number(milestoneCount) }, (_, i) =>
      publicClient.readContract({ ...e, functionName: "milestones", args: [BigInt(i)] }),
    ),
  );

  const balance = await publicClient.readContract({
    ...paymentToken,
    functionName: "balanceOf",
    args: [escrow],
  });

  return {
    address: escrow,
    totalProjectBudget: weiToGES(totalProjectBudget),
    feeReserve: weiToGES(feeReserve),
    totalReleased: weiToGES(totalReleased),
    settlementPaid: weiToGES(settlementPaid),
    totalReturnedOnCancellation: weiToGES(totalReturnedOnCancellation),
    totalSweptToTreasury: weiToGES(totalSweptToTreasury),
    feesCollected: weiToGES(feesCollected),
    totalUncollectedFees: weiToGES(totalUncollectedFees),
    balance: weiToGES(balance),
    currentMilestoneIndex: currentMilestoneIndex.toString(),
    cancelled,
    committeeFinalized,
    treasuryWallet,
    builderSigner,
    memberSigners,
    alternates,
    milestones: milestones.map((m) => ({
      amount: weiToGES(m[0]),
      evidenceHash: m[1],
      released: m[2],
    })),
  };
}

export async function hasVoted(governance: Address, voter: Address): Promise<boolean> {
  return publicClient.readContract({
    ...governanceAt(governance),
    functionName: "hasVoted",
    args: [voter],
  });
}

export async function optedIn(governance: Address, member: Address): Promise<boolean> {
  return publicClient.readContract({
    ...governanceAt(governance),
    functionName: "optedIn",
    args: [member],
  });
}

export async function feeCredit(escrow: Address, member: Address): Promise<string> {
  const c = await publicClient.readContract({
    ...escrowAt(escrow),
    functionName: "feeCredits",
    args: [member],
  });
  return weiToGES(c);
}

export async function hasSignedMilestone(
  escrow: Address,
  index: number,
  signer: Address,
): Promise<boolean> {
  return publicClient.readContract({
    ...escrowAt(escrow),
    functionName: "hasSigned",
    args: [BigInt(index), signer],
  });
}