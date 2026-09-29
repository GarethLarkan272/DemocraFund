import { NextResponse } from "next/server";
import { keccak256, encodeFunctionData, type Address } from "viem";
import { requireUser, accountFor, apiError } from "@/lib/api";
import { submit } from "@/lib/relay";
import { redemption, paymentToken, publicClient, escrowAt } from "@/lib/chain";
import { companyWallets } from "@/lib/wallets";
import { TO_WEI, weiToGES } from "@/lib/config";
import { prisma } from "@/lib/db";
import { loadProjectSummary } from "@/lib/project";

// The wallet behind the session: companies sign from their identity wallet;
// members from their derived wallet. Both are where milestone payouts and
// committee fees land.
function walletFor(session: { role: string; username: string }) {
  return session.role === "company" ? companyWallets(session.username).admin : accountFor(session);
}

// The escrows the caller has actually earned from: tenders their company won
// (milestone payouts) and tenders where they are a drawn committee member
// (fees). A redemption must be attributed to one of these - the receipt's
// provenance is the project that paid the redeemer, not their own wallet.
export async function provenanceFor(session: { role: string; username: string }) {
  const wallet = walletFor(session);
  const projects = await prisma.project.findMany({ orderBy: { createdAt: "desc" } });
  const out: { governance: string; escrow: string; title: string }[] = [];
  for (const p of projects) {
    let escrow: string | null = p.escrowAddress;
    let title = p.title;
    try {
      const summary = await loadProjectSummary(p.governance as `0x${string}`);
      title = summary.title;
      escrow = summary.escrowAddress;
      if (escrow !== "0x0000000000000000000000000000000000000000") {
        await prisma.project.update({
          where: { governance: p.governance },
          data: { escrowAddress: escrow.toLowerCase() },
        });
      }
    } catch {
      // keep the cached value
    }
    if (!escrow || escrow === "0x0000000000000000000000000000000000000000") continue;

    // Provenance check: the caller must be the escrow's builder (company) or
    // a drawn member (fees). Two cheap reads instead of a full project load.
    const escrowAddr = escrow as Address;
    const walletAddress = wallet.address.toLowerCase();
    if (session.role === "company") {
      const builder = (await publicClient.readContract({
        ...escrowAt(escrowAddr),
        functionName: "builderSigner",
      })) as Address;
      if (builder.toLowerCase() !== walletAddress) continue;
    } else {
      const members = (await publicClient.readContract({
        ...escrowAt(escrowAddr),
        functionName: "getMemberSigners",
      })) as Address[];
      if (!members.map((m) => m.toLowerCase()).includes(walletAddress)) continue;
    }
    out.push({ governance: p.governance, escrow: escrow.toLowerCase(), title });
  }
  return out;
}

// GET /api/redeem - the caller's GES balance, their redemption receipts, and
// the escrows their earnings came from (provenance choices for redemption).
export async function GET() {
  const auth = await requireUser();
  if ("error" in auth) return auth.error;
  try {
    const wallet = walletFor(auth.session);
    const balance = await publicClient.readContract({
      ...paymentToken,
      functionName: "balanceOf",
      args: [wallet.address],
    });

    const count = Number(
      await publicClient.readContract({ ...redemption, functionName: "receiptCount" }),
    );
    const mine: { tokenId: string; amount: string; state: string; payoutRef: string }[] = [];
    for (let i = 1; i <= count; i++) {
      const r = await publicClient.readContract({
        ...redemption,
        functionName: "receipts",
        args: [BigInt(i)],
      });
      if (r[0].toLowerCase() === wallet.address.toLowerCase()) {
        mine.push({
          tokenId: String(i),
          amount: weiToGES(r[2]),
          state: ["Pending", "Paid", "Rejected"][Number(r[4])],
          payoutRef: r[5],
        });
      }
    }

    return NextResponse.json({
      balance: weiToGES(balance),
      wallet: wallet.address,
      receipts: mine.reverse(),
      provenance: await provenanceFor(auth.session),
    });
  } catch (e) {
    return apiError(e);
  }
}

// POST /api/redeem { amount, destinationId?, escrow? }
// Any GES holder burns their balance at the off-ramp and receives a receipt
// NFT. The receipt's provenance escrow is the project that paid the redeemer;
// when the caller has no project earnings (e.g. never drawn to a committee),
// their own wallet is recorded as the provenance.
export async function POST(req: Request) {
  const auth = await requireUser();
  if ("error" in auth) return auth.error;
  try {
    const { amount, destinationId, escrow } = await req.json();
    if (!amount || Number(amount) <= 0) {
      return NextResponse.json({ error: "Enter an amount greater than zero" }, { status: 400 });
    }
    const wallet = walletFor(auth.session);
    const destHash = keccak256(Buffer.from(String(destinationId || "bank-account")));

    // Provenance validation: the escrow must be one the caller actually earned
    // from (a won tender's escrow, or a committee they're drawn to), or their
    // own wallet when they have no project earnings. Unknown escrows are
    // rejected so receipts never carry fabricated provenance.
    let escrowAddr: Address = wallet.address as Address;
    if (escrow) {
      const choices = await provenanceFor(auth.session);
      const match = choices.find((c) => c.escrow.toLowerCase() === String(escrow).toLowerCase());
      if (!match) {
        return NextResponse.json(
          { error: "That escrow is not one you have earned from - pick one of your tenders" },
          { status: 400 },
        );
      }
      escrowAddr = match.escrow as Address;
    }

    // 1. Approve the Redemption contract to pull the GES.
    const approveData = encodeFunctionData({
      abi: paymentToken.abi,
      functionName: "approve",
      args: [redemption.address, TO_WEI(amount)],
    });
    await submit(wallet, { to: paymentToken.address, data: approveData }, "approve");

    // 2. Redeem: burn GES, mint the receipt NFT.
    const redeemData = encodeFunctionData({
      abi: redemption.abi,
      functionName: "redeem",
      args: [TO_WEI(amount), destHash, escrowAddr],
    });
    const receipt = await submit(wallet, { to: redemption.address, data: redeemData }, "redeem");

    const tokenId = Number(
      await publicClient.readContract({ ...redemption, functionName: "receiptCount" }),
    );

    return NextResponse.json({ ok: true, txHash: receipt.hash, tokenId });
  } catch (e) {
    return apiError(e);
  }
}