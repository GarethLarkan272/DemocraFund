import { NextResponse } from "next/server";
import { encodeFunctionData, keccak256 } from "viem";
import { getSession } from "@/lib/auth";
import { apiError } from "@/lib/api";
import { submit } from "@/lib/relay";
import { redemption } from "@/lib/chain";
import { deriveRoleWallet } from "@/lib/wallets";
import { prisma } from "@/lib/db";

// POST /api/payer/decide - multipart:
//   tokenId, decision ("accepted"|"rejected"),
//   payoutRef? (accepted), proofFile? (accepted - proof of payment doc),
//   reason? (rejected - plain text justification)
export async function POST(req: Request) {
  const session = await getSession();
  if (!session || session.role !== "payer") {
    return NextResponse.json({ error: "Payer role required" }, { status: 403 });
  }
  try {
    const form = await req.formData();
    const tokenId = Number(form.get("tokenId"));
    const decision = String(form.get("decision") ?? "");
    const payoutRef = String(form.get("payoutRef") ?? "").trim();
    const reason = String(form.get("reason") ?? "").trim();
    const proofFile = form.get("proofFile") as File | null;

    if (!tokenId) return NextResponse.json({ error: "Receipt tokenId is required" }, { status: 400 });

    const payer = deriveRoleWallet("payer");
    const txHashes: string[] = [];

    if (decision === "accepted") {
      if (!payoutRef) {
        return NextResponse.json({ error: "A payment reference is required for an accepted payment" }, { status: 400 });
      }
      const data = encodeFunctionData({
        abi: redemption.abi,
        functionName: "markPaid",
        args: [BigInt(tokenId), payoutRef],
      });
      const receipt = await submit(payer, { to: redemption.address, data }, "markPaid");
      txHashes.push(receipt.hash);

      // Store the proof-of-payment document (off-chain; the payout ref is the
      // on-chain certification).
      if (proofFile) {
        await prisma.document.create({
          data: {
            kind: "redemption",
            contentHash: keccak256(new Uint8Array(await proofFile.arrayBuffer())),
            fileName: proofFile.name,
            mimeType: proofFile.type,
            data: new Uint8Array(await proofFile.arrayBuffer()),
          },
        });
      }
      return NextResponse.json({ ok: true, txHashes, tokenId, decision: "accepted" });
    }

    if (decision === "rejected") {
      if (!reason) {
        return NextResponse.json({ error: "A reason is required for a rejection" }, { status: 400 });
      }
      const reasonHash = keccak256(Buffer.from(reason));
      const data = encodeFunctionData({
        abi: redemption.abi,
        functionName: "markRejected",
        args: [BigInt(tokenId), reasonHash],
      });
      const receipt = await submit(payer, { to: redemption.address, data }, "markRejected");
      txHashes.push(receipt.hash);

      // Keep the human-readable reason next to its hash.
      await prisma.document.create({
        data: {
          kind: "redemption",
          contentHash: reasonHash,
          fileName: `rejection-${tokenId}.txt`,
          mimeType: "text/plain",
          data: Buffer.from(reason),
        },
      });
      return NextResponse.json({ ok: true, txHashes, tokenId, decision: "rejected" });
    }

    return NextResponse.json({ error: "Decision must be accepted or rejected" }, { status: 400 });
  } catch (e) {
    return apiError(e);
  }
}