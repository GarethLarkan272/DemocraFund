import { NextResponse } from "next/server";
import { keccak256, encodeFunctionData, stringToHex, padHex } from "viem";
import { requireUser, accountFor, apiError } from "@/lib/api";
import { submit, sponsorAccount } from "@/lib/relay";
import { projectFactory, publicClient } from "@/lib/chain";
import { deriveRoleWallet } from "@/lib/wallets";
import { prisma } from "@/lib/db";
import { VRF_SUBSCRIPTION_ID, TO_WEI } from "@/lib/config";

const PROJECT_CREATED_TOPIC =
  "0x3815a547ca4b753ae5cc6a73f3e019b6791faedad7fe0614a6e08d0bcfb137f1";
const VRF_COORDINATOR = "0x5CE8D5A2BC84beb22a398CCA51996F7930313D61";

export async function POST(req: Request) {
  const auth = await requireUser();
  if ("error" in auth) return auth.error;
  if (auth.session.role !== "committee") {
    return NextResponse.json({ error: "Only the committee can create tenders" }, { status: 403 });
  }

  try {
    const form = await req.formData();
    const title = String(form.get("title") ?? "");
    const description = String(form.get("description") ?? "");
    const department = String(form.get("department") ?? "");
    const category = String(form.get("category") ?? "");
    const budgetCap = String(form.get("budgetCap") ?? "");
    const fee = String(form.get("committeeFeePerSignature") ?? "0");
    const proposalDeadline = Number(form.get("proposalDeadline") ?? "0");
    const votingDeadline = Number(form.get("votingDeadline") ?? "0");
    const awardDeadline = Number(form.get("awardDeadline") ?? "0");
    const specFile = form.get("specFile") as File | null;

    if (!title || !department || !category || !budgetCap) {
      return NextResponse.json({ error: "Missing required fields" }, { status: 400 });
    }

    // Absolute timestamps (unix seconds) picked on the form. The contract wants
    // the award window as a duration (deliberationWindow), derived here as the
    // time between voting closing and the award deadline.
    const now = Math.floor(Date.now() / 1000);
    if (!proposalDeadline || !votingDeadline || !awardDeadline) {
      return NextResponse.json({ error: "All three deadline dates are required" }, { status: 400 });
    }
    if (proposalDeadline <= now || votingDeadline <= proposalDeadline || awardDeadline <= votingDeadline) {
      return NextResponse.json(
        { error: "Dates must be in the future and in order: bidding closes first, then voting, then the award deadline" },
        { status: 400 },
      );
    }
    const deliberationSec = awardDeadline - votingDeadline;
    const toBytes32 = (s: string) =>
      padHex(stringToHex(s.slice(0, 31), { size: 32 }), { dir: "right" });

    // Hash the tender spec (stored locally; the hash is the on-chain truth).
    // The description is folded into the hash so the on-chain commitment
    // covers what the committee actually said the work is.
    const specBytes = specFile ? Buffer.from(await specFile.arrayBuffer()) : Buffer.from(`Tender: ${title}`);
    const descriptionBytes = Buffer.from(description || `Tender: ${title}`);
    const contentHash = keccak256(Buffer.concat([specBytes, descriptionBytes]));

    const images: { file: File; bytes: Buffer }[] = [];
    for (const key of form.keys()) {
      if (key.startsWith("image_")) {
        const img = form.get(key) as File;
        if (img) images.push({ file: img, bytes: Buffer.from(await img.arrayBuffer()) });
      }
    }

    const committee = accountFor(auth.session);
    const treasury = deriveRoleWallet("treasury");

    const config = {
      budgetCap: TO_WEI(budgetCap),
      committeeFeePerSignature: TO_WEI(fee),
      title: toBytes32(title),
      category: toBytes32(category),
      department: toBytes32(department),
      specContentHash: contentHash,
      ipfsHash: contentHash,
      proposalDeadline: BigInt(proposalDeadline),
      votingDeadline: BigInt(votingDeadline),
      deliberationWindow: BigInt(deliberationSec),
      governanceSafeWallet: committee.address,
      treasuryWallet: treasury.address,
    };

    const data = encodeFunctionData({
      abi: projectFactory.abi,
      functionName: "createProject",
      args: [config],
    });

    const receipt = await submit(committee, { to: projectFactory.address, data }, "createProject");

    // The factory emits ProjectCreated(governance) - decode it from the logs.
    const logs = await publicClient.getTransactionReceipt({ hash: receipt.hash as `0x${string}` });
    const createdLog = logs.logs.find((l) => l.topics[0] === PROJECT_CREATED_TOPIC);
    if (!createdLog || !createdLog.topics[1]) {
      return NextResponse.json({ error: "Project created but address could not be decoded" }, { status: 500 });
    }
    const governance = `0x${createdLog.topics[1].slice(26)}` as `0x${string}`;

    // Register the governance as a VRF consumer (must exist before the award draw).
    // addConsumer must come from the subscription owner - the sponsor wallet.
    await submit(
      sponsorAccount,
      {
        to: VRF_COORDINATOR,
        data: encodeFunctionData({
          abi: [
            {
              type: "function",
              name: "addConsumer",
              stateMutability: "nonpayable",
              inputs: [
                { type: "uint256", name: "subId" },
                { type: "address", name: "consumer" },
              ],
              outputs: [],
            },
          ],
          functionName: "addConsumer",
          args: [BigInt(VRF_SUBSCRIPTION_ID), governance],
        }),
      },
      "addConsumer",
    ).catch(() => null);

    await prisma.project.create({
      data: {
        governance: governance.toLowerCase(),
        factory: projectFactory.address.toLowerCase(),
        title,
        department,
        category,
        description: description || null,
        ipfsHash: contentHash,
      },
    });
    if (specFile) {
      await prisma.document.create({
        data: {
          kind: "tender",
          contentHash,
          fileName: specFile.name,
          mimeType: specFile.type,
          data: specBytes,
          project: { connect: { governance: governance.toLowerCase() } },
        },
      });
    }
    for (const img of images) {
      await prisma.document.create({
        data: {
          kind: "tender",
          contentHash: keccak256(img.bytes),
          fileName: img.file.name,
          mimeType: img.file.type,
          data: new Uint8Array(img.bytes),
          project: { connect: { governance: governance.toLowerCase() } },
        },
      });
    }

    return NextResponse.json({ ok: true, governance, txHash: receipt.hash });
  } catch (e) {
    return apiError(e);
  }
}