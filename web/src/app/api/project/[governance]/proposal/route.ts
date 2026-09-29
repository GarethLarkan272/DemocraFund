import { NextResponse } from "next/server";
import { keccak256, encodeFunctionData, type Address } from "viem";
import { requireUser, companyForUser, apiError } from "@/lib/api";
import { submit } from "@/lib/relay";
import { governanceAt, publicClient } from "@/lib/chain";
import { companyWallets } from "@/lib/wallets";
import { prisma } from "@/lib/db";
import { TO_WEI } from "@/lib/config";

export async function POST(req: Request, { params }: { params: Promise<{ governance: string }> }) {
  const auth = await requireUser();
  if ("error" in auth) return auth.error;
  if (auth.session.role !== "company") {
    return NextResponse.json({ error: "Only companies can bid" }, { status: 403 });
  }

  try {
    const { governance } = await params;
    const form = await req.formData();
    const cost = String(form.get("cost") ?? "");
    const milestones = (JSON.parse(String(form.get("milestones") ?? "[]")) as (string | number)[]).map(String);
    const depositRequired = form.get("depositRequired") === "true";
    const specFile = form.get("specFile") as File | null;

    const company = await companyForUser(auth.session.userId);
    if (!company) {
      return NextResponse.json({ error: "Register your company first" }, { status: 400 });
    }

    if (!cost || !milestones.length) {
      return NextResponse.json({ error: "Cost and at least one milestone are required" }, { status: 400 });
    }
    const costNum = Number(cost);
    const sum = milestones.reduce((s, m) => s + Number(m), 0);
    if (milestones.some((m) => !m || Number(m) <= 0)) {
      return NextResponse.json({ error: "Every milestone amount must be greater than zero" }, { status: 400 });
    }
    if (TO_WEI(milestones.reduce((s, m) => s + Number(m), 0)) !== TO_WEI(cost)) {
      return NextResponse.json(
        { error: `Milestones sum to R${sum} but your price is R${costNum} — they must match` },
        { status: 400 },
      );
    }
    if (depositRequired && Number(milestones[0]) <= 0) {
      return NextResponse.json(
        { error: "A deposit is required, so milestone 1's amount is the deposit — set it above zero" },
        { status: 400 },
      );
    }

    // The proposal document's content hash is the on-chain truth; the file is
    // stored locally so the committee can view what the hash commits to.
    const specBytes = specFile
      ? Buffer.from(await specFile.arrayBuffer())
      : Buffer.from(`Bid: ${company.name} for R${cost}`);
    const contentHash = keccak256(specBytes);

    const data = encodeFunctionData({
      abi: governanceAt(governance as Address).abi,
      functionName: "createProposal",
      args: [
        BigInt(company.onChainId),
        contentHash,
        contentHash,
        TO_WEI(cost),
        depositRequired,
        milestones.map((m) => ({ amount: TO_WEI(m), evidenceHash: "0x0000000000000000000000000000000000000000000000000000000000000000" as const, released: false })),
      ],
    });

    const account = companyWallets(auth.session.username).admin;
    const receipt = await submit(account, { to: governance as Address, data }, "createProposal");

    // Mirror the bid locally (the on-chain getter omits the milestones array).
    const count = Number(
      await publicClient.readContract({
        ...governanceAt(governance as Address),
        functionName: "numberOfProposals",
      }),
    );

    const projectRow = await prisma.project.findUnique({ where: { governance: governance.toLowerCase() } });
    if (!projectRow) {
      return NextResponse.json({ error: "Project not found in the app registry" }, { status: 404 });
    }
    const createdProposal = await prisma.proposal.create({
      data: {
        governance: governance.toLowerCase(),
        proposalId: count - 1,
        companyName: company.name,
        cost,
        milestones: JSON.stringify(milestones),
        specContentHash: contentHash,
        ipfsHash: contentHash,
        depositRequired,
      },
    });
    if (specFile) {
      await prisma.document.create({
        data: {
          kind: "proposal",
          contentHash,
          fileName: specFile.name,
          mimeType: specFile.type,
          data: specBytes,
          project: { connect: { governance: governance.toLowerCase() } },
          proposal: { connect: { id: createdProposal.id } },
        },
      });
    }

    return NextResponse.json({ ok: true, txHash: receipt.hash });
  } catch (e) {
    return apiError(e);
  }
}