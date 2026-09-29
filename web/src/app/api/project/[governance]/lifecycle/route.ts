import { NextResponse } from "next/server";
import { encodeFunctionData, type Address } from "viem";
import { requireUser, accountFor, apiError } from "@/lib/api";
import { submit } from "@/lib/relay";
import { governanceAt, publicClient } from "@/lib/chain";
import { friendlyLifecycleError } from "@/lib/errors";

// POST /api/project/[governance]/lifecycle { action, proposalId?, shortlistSize? }
// action: acceptProposals | openVoting | closeVoting | award | expire | complete | retry
export async function POST(req: Request, { params }: { params: Promise<{ governance: string }> }) {
  const auth = await requireUser();
  if ("error" in auth) return auth.error;
  if (auth.session.role !== "committee") {
    return NextResponse.json({ error: "Only the committee drives the lifecycle" }, { status: 403 });
  }
  const { governance } = await params;
  try {
    const { action, proposalId, shortlistSize, deadlineExtensionDays } = await req.json();

    let functionName: string;
    let args: readonly unknown[] = [];
    switch (action) {
      case "acceptProposals":
        functionName = "acceptProposals";
        break;
      case "openVoting":
        functionName = "closeProposalsAndOpenVoting";
        break;
      case "closeVoting": {
        // The shortlist is computed from the live vote record and verified
        // on-chain: exactly the top-N proposals by votes, boundary ties all
        // admitted. The committee only declares the size.
        functionName = "closeVoting";
        const g = governanceAt(governance as Address);
        const n = Number(shortlistSize ?? 1);
        const count = Number(
          await publicClient.readContract({ ...g, functionName: "numberOfProposals" }),
        );
        const votes: bigint[] = [];
        for (let i = 0; i < count; i++) {
          votes.push(
            (await publicClient.readContract({
              ...g,
              functionName: "numberOfVotesPerProposal",
              args: [BigInt(i)],
            })) as bigint,
          );
        }
        const sorted = [...votes].sort((a, b) => (a < b ? -1 : a > b ? 1 : 0));
        const threshold = count > 0 ? sorted[Math.max(count - n, 0)] : BigInt(0);
        const shortlist = votes
          .map((v, i) => ({ v, i }))
          .filter(({ v }) => v >= threshold)
          .map(({ i }) => BigInt(i));
        args = [BigInt(n), shortlist];
        break;
      }
      case "award":
        functionName = "awardProposal";
        args = [BigInt(proposalId)];
        break;
      case "expire":
        functionName = "expireDeliberation";
        break;
      case "complete":
        functionName = "completeProject";
        break;
      case "retry":
        functionName = "retryCommitteeSelection";
        break;
      case "extend": {
        // Dead-tender rescue: extend the proposal + voting deadlines when the
        // window closed with no bids (contract-enforced: PROPOSAL only, admin
        // only, deadline passed, zero proposals).
        functionName = "extendProposalDeadline";
        const seconds = Number(deadlineExtensionDays ?? 0) * 86400;
        if (seconds <= 0) {
          return NextResponse.json({ error: "Enter an extension of at least one day" }, { status: 400 });
        }
        args = [BigInt(seconds)];
        break;
      }
      case "cancel":
        // Pre-award cancellation (no escrow yet): admin-only, returns nothing
        // to the treasury because nothing was funded. Post-award cancellation
        // goes through the escrow multisig instead.
        functionName = "cancelProject";
        break;
      default:
        return NextResponse.json({ error: `Unknown action: ${action}` }, { status: 400 });
    }

    const data = encodeFunctionData({
      abi: governanceAt(governance as Address).abi,
      functionName: functionName as never,
      args: args as never,
    });

    // Simulate first: a reverting action should tell the user why (with time
    // remaining), not burn a broadcast that fails.
    try {
      await publicClient.call({
        account: accountFor(auth.session).address,
        to: governance as Address,
        data,
      });
    } catch (simErr) {
      const friendly = await friendlyLifecycleError(simErr, governance as Address);
      if (friendly) return NextResponse.json({ error: friendly }, { status: 400 });
    }

    const receipt = await submit(accountFor(auth.session), { to: governance as Address, data }, action);
    return NextResponse.json({ ok: true, txHash: receipt.hash });
  } catch (e) {
    const friendly = await friendlyLifecycleError(e, governance as Address).catch(() => null);
    if (friendly) return NextResponse.json({ error: friendly }, { status: 400 });
    return apiError(e);
  }
}