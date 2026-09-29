import { NextResponse } from "next/server";
import { keccak256, encodeFunctionData } from "viem";
import { requireUser, companyForUser, apiError } from "@/lib/api";
import { submit } from "@/lib/relay";
import { companyRegistry, publicClient } from "@/lib/chain";
import { companyWallets } from "@/lib/wallets";
import { prisma } from "@/lib/db";

// PATCH /api/company/update - multipart form:
//   infoFile? (new info doc) | active? ("true"/"false" to toggle)
export async function PATCH(req: Request) {
  const auth = await requireUser();
  if ("error" in auth) return auth.error;
  if (auth.session.role !== "company") {
    return NextResponse.json({ error: "Only companies can update their details" }, { status: 403 });
  }
  try {
    const company = await companyForUser(auth.session.userId);
    if (!company) {
      return NextResponse.json({ error: "Register your company first" }, { status: 400 });
    }

    const form = await req.formData();
    const activeParam = form.get("active");
    const infoFile = form.get("infoFile") as File | null;

    const account = companyWallets(auth.session.username).admin;

    // The registry requires a valid infoHash - carry forward the current one
    // unless a new document is being committed.
    let infoHash = company.infoHash as `0x${string}`;
    if (infoFile) {
      infoHash = keccak256(new Uint8Array(await infoFile.arrayBuffer()));
    }

    const [chainCompany, onChainId] = await Promise.all([
      publicClient.readContract({
        ...companyRegistry,
        functionName: "companies",
        args: [BigInt(company.onChainId)],
      }),
      publicClient.readContract({
        ...companyRegistry,
        functionName: "companyIdOfAdmin",
        args: [account.address],
      }),
    ]);

    const txHashes: string[] = [];
    if (infoFile || infoHash !== chainCompany[1]) {
      const data = encodeFunctionData({
        abi: companyRegistry.abi,
        functionName: "updateCompany",
        args: [infoHash],
      });
      const receipt = await submit(account, { to: companyRegistry.address, data }, "updateCompany");
      txHashes.push(receipt.hash);
    }

    let active = chainCompany[2];
    if (activeParam !== null) {
      const next = activeParam === "true";
      if (next !== active) {
        const data = encodeFunctionData({
          abi: companyRegistry.abi,
          functionName: "setCompanyActive",
          args: [next],
        });
        const receipt = await submit(account, { to: companyRegistry.address, data }, "setCompanyActive");
        txHashes.push(receipt.hash);
        active = next;
      }
    }

    await prisma.company.update({
      where: { id: company.id },
      data: {
        infoHash,
        active,
      },
    });

    return NextResponse.json({
      ok: true,
      txHashes,
      companyId: Number(onChainId),
      infoHash,
      active,
    });
  } catch (e) {
    return apiError(e);
  }
}