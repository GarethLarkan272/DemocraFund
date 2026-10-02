import { NextResponse } from "next/server";
import { keccak256, encodeFunctionData } from "viem";
import { requireUser, apiError } from "@/lib/api";
import { submit } from "@/lib/relay";
import { companyRegistry, publicClient } from "@/lib/chain";
import { companyWallets } from "@/lib/wallets";
import { prisma } from "@/lib/db";

// GET /api/company/register - the caller's company (active state read live from chain)
export async function GET() {
  const auth = await requireUser();
  if ("error" in auth) return auth.error;
  const company = await prisma.company.findUnique({ where: { userId: auth.session.userId } });
  if (!company) return NextResponse.json({ company: null });
  let active = company.active;
  try {
    const chain = await publicClient.readContract({
      ...companyRegistry,
      functionName: "companies",
      args: [BigInt(company.onChainId)],
    });
    active = chain[2];
  } catch {
    // fall back to the mirror
  }
  return NextResponse.json({ company: { ...company, active } });
}

// POST /api/company/register { name }
export async function POST(req: Request) {
  const auth = await requireUser();
  if ("error" in auth) return auth.error;
  if (auth.session.role !== "company") {
    return NextResponse.json({ error: "Sign up as a company to register one" }, { status: 403 });
  }
  try {
    const { name } = await req.json();
    if (!name) return NextResponse.json({ error: "Company name is required" }, { status: 400 });

    const existing = await prisma.company.findUnique({ where: { userId: auth.session.userId } });
    if (existing) {
      return NextResponse.json({ error: "You already registered a company" }, { status: 400 });
    }

    const { admin } = companyWallets(auth.session.username);
    const infoHash = keccak256(Buffer.from(`company:${name}`));

    const data = encodeFunctionData({
      abi: companyRegistry.abi,
      functionName: "registerCompany",
      args: [infoHash],
    });

    let receipt: { hash: string } | undefined;
    try {
      receipt = await submit(admin, { to: companyRegistry.address, data }, "registerCompany");
    } catch {
      // Already registered on-chain (e.g. DB was reset but the chain remembers) -
      // recover the existing company id instead of failing.
    }

    const onChainId = Number(
      await publicClient.readContract({
        ...companyRegistry,
        functionName: "companyIdOfAdmin",
        args: [admin.address],
      }),
    );
    if (onChainId === 0) {
      return NextResponse.json({ error: "On-chain registration failed" }, { status: 400 });
    }

    await prisma.company.create({
      data: {
        name,
        onChainId,
        adminWallet: admin.address.toLowerCase(),
        infoHash,
        user: { connect: { id: auth.session.userId } },
      },
    });

    return NextResponse.json({ ok: true, txHash: receipt?.hash, companyId: onChainId });
  } catch (e) {
    return apiError(e);
  }
}