import { NextResponse } from "next/server";
import { keccak256, encodeFunctionData, type Address, type Hex } from "viem";
import { requireUser, accountFor, apiError } from "@/lib/api";
import { submit } from "@/lib/relay";
import { escrowAt, governanceAt, publicClient } from "@/lib/chain";
import { companyWallets } from "@/lib/wallets";
import { milestoneSigs } from "@/lib/eip712";
import { prisma } from "@/lib/db";

// POST /api/project/[governance]/milestone
//   FormData { action: "submit", milestoneIndex, evidenceFile? }   -> builder
//   JSON     { action: "approve", milestoneIndex }                 -> committee/member signer
export async function POST(req: Request, { params }: { params: Promise<{ governance: string }> }) {
  const auth = await requireUser();
  if ("error" in auth) return auth.error;

  try {
    const { governance } = await params;
    const g = governanceAt(governance as Address);

    const escrowAddr = (await publicClient.readContract({
      ...g,
      functionName: "projectEscrow",
    })) as Address;
    if (escrowAddr === "0x0000000000000000000000000000000000000000") {
      return NextResponse.json({ error: "No escrow yet - project not awarded" }, { status: 400 });
    }

    const contentType = req.headers.get("content-type") ?? "";
    if (contentType.includes("multipart")) {
      // ---- Builder submits milestone completion with evidence ----
      if (auth.session.role !== "company") {
        return NextResponse.json({ error: "Only the builder can submit completion" }, { status: 403 });
      }
      const form = await req.formData();
      const milestoneIndex = Number(form.get("milestoneIndex"));
      const file = form.get("evidenceFile") as File | null;

      const company = await prisma.company.findUnique({ where: { userId: auth.session.userId } });
      const builderWallet = companyWallets(auth.session.username).admin;
      const evidenceBytes = file
        ? Buffer.from(await file.arrayBuffer())
        : Buffer.from(`milestone ${milestoneIndex} evidence`);
      const evidenceHash = keccak256(evidenceBytes);

      const data = encodeFunctionData({
        abi: escrowAt(escrowAddr).abi,
        functionName: "submitMilestoneComplete",
        args: [evidenceHash],
      });
      const receipt = await submit(builderWallet, { to: escrowAddr, data }, "submitMilestoneComplete");

      if (file) {
        await prisma.document.create({
          data: {
            kind: "evidence",
            contentHash: evidenceHash,
            fileName: file.name,
            mimeType: file.type,
            data: evidenceBytes,
            project: { connect: { governance: governance.toLowerCase() } },
          },
        });
      }
      return NextResponse.json({ ok: true, txHash: receipt.hash, evidenceHash });
    }

    // ---- A signer approves the current milestone ----
    const { action, milestoneIndex } = await req.json();
    if (action !== "approve") {
      return NextResponse.json({ error: "Unknown action" }, { status: 400 });
    }

    const account = accountFor(auth.session);
    const escrow = escrowAt(escrowAddr);

    const currentIndex = Number(
      await publicClient.readContract({ ...escrow, functionName: "currentMilestoneIndex" }),
    );
    const index = milestoneIndex ?? currentIndex;

    const evidenceHash = (await publicClient.readContract({
      ...escrow,
      functionName: "milestones",
      args: [BigInt(index)],
    }))[1] as Hex;
    if (evidenceHash === "0x0000000000000000000000000000000000000000000000000000000000000000") {
      return NextResponse.json({ error: "The builder has not submitted evidence yet" }, { status: 400 });
    }

    // Gate: the caller's wallet must be the admin or a drawn committee member.
    const safeWallet = (await publicClient.readContract({ ...g, functionName: "projectGovernanceSafeWallet" })) as Address;
    const memberSigners = (await publicClient.readContract({
      ...escrow,
      functionName: "getMemberSigners",
    })) as Address[];

    if (account.address.toLowerCase() !== safeWallet.toLowerCase() &&
        !memberSigners.some((m) => m.toLowerCase() === account.address.toLowerCase())) {
      return NextResponse.json(
        { error: "Your account is not a signer on this escrow (admin or drawn member)" },
        { status: 403 },
      );
    }

    const sig = await milestoneSigs(account, escrowAddr, index, evidenceHash);
    const data = encodeFunctionData({
      abi: escrow.abi,
      functionName: "approveMilestone",
      args: [[sig]],
    });
    const receipt = await submit(account, { to: escrowAddr, data }, "approveMilestone");
    return NextResponse.json({ ok: true, txHash: receipt.hash });
  } catch (e) {
    return apiError(e);
  }
}