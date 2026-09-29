import { NextResponse } from "next/server";
import { keccak256, encodeFunctionData } from "viem";
import { prisma } from "@/lib/db";
import { hashPassword } from "@/lib/password";
import { createSession } from "@/lib/auth";
import { submit } from "@/lib/relay";
import { companyRegistry, publicClient } from "@/lib/chain";
import { companyWallets } from "@/lib/wallets";

export async function POST(req: Request) {
  try {
    const form = await req.formData();
    const username = String(form.get("username") ?? "");
    const email = String(form.get("email") ?? "") || null;
    const password = String(form.get("password") ?? "");
    const role = String(form.get("role") ?? "member");
    const companyName = String(form.get("companyName") ?? "");
    const infoFile = form.get("infoFile") as File | null;

    if (!username || !password || password.length < 6) {
      return NextResponse.json({ error: "Username and a 6+ char password are required" }, { status: 400 });
    }
    const cleanRole = ["member", "company", "committee", "payer"].includes(role) ? role : "member";

    // Usernames are unique — surface it nicely instead of a raw Prisma
    // unique-constraint crash.
    if (await prisma.user.findUnique({ where: { username } })) {
      return NextResponse.json({ error: "That username is already taken — try another" }, { status: 400 });
    }

    // There is exactly ONE committee identity on-chain (the club committee's
    // custodial wallet) - only the first committee signup may hold it.
    if (cleanRole === "committee") {
      const existing = await prisma.user.findFirst({ where: { role: "committee" } });
      if (existing) {
        return NextResponse.json({ error: "A committee account already exists" }, { status: 400 });
      }
    }

    // A company signup registers the company on-chain immediately. The admin
    // (identity) wallet is derived for the user and is also the payout wallet.
    // The info document's hash is the on-chain commitment to their details.
    if (cleanRole === "company" && !companyName) {
      return NextResponse.json({ error: "Company name is required" }, { status: 400 });
    }

    const user = await prisma.user.create({
      data: {
        username,
        email,
        passwordHash: hashPassword(password),
        role: cleanRole,
      },
    });

    let companyId: number | null = null;
    if (cleanRole === "company") {
      const { admin } = companyWallets(username);
      const infoBytes = infoFile
        ? Buffer.from(await infoFile.arrayBuffer())
        : Buffer.from(`company:${companyName}`);
      const infoHash = keccak256(infoBytes);

      try {
        const data = encodeFunctionData({
          abi: companyRegistry.abi,
          functionName: "registerCompany",
          args: [infoHash],
        });
        await submit(admin, { to: companyRegistry.address, data }, "registerCompany");
      } catch {
        // Already registered on-chain (e.g. DB was reset but the chain
        // remembers) - recover the existing id instead of failing.
      }

      const onChainId = Number(
        await publicClient.readContract({
          ...companyRegistry,
          functionName: "companyIdOfAdmin",
          args: [admin.address],
        }),
      );
      if (onChainId === 0) {
        await prisma.user.delete({ where: { id: user.id } });
        return NextResponse.json({ error: "On-chain company registration failed" }, { status: 400 });
      }

      await prisma.company.create({
        data: {
          name: companyName,
          onChainId,
          adminWallet: admin.address.toLowerCase(),
          infoHash,
          user: { connect: { id: user.id } },
        },
      });
      if (infoFile) {
        await prisma.document.create({
          data: {
            kind: "tender",
            contentHash: infoHash,
            fileName: infoFile.name,
            mimeType: infoFile.type,
            data: infoBytes,
            user: { connect: { id: user.id } },
          },
        });
      }
      companyId = onChainId;
    }

    await createSession(user);
    return NextResponse.json({
      ok: true,
      user: { id: user.id, username: user.username, role: user.role },
      companyId,
    });
  } catch (e) {
    return NextResponse.json({ error: e instanceof Error ? e.message : "Signup failed" }, { status: 400 });
  }
}