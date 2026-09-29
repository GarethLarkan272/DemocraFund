import { NextResponse } from "next/server";
import { prisma } from "@/lib/db";
import { verifyPassword } from "@/lib/password";
import { createSession } from "@/lib/auth";

export async function POST(req: Request) {
  const { username, password } = await req.json();
  const user = await prisma.user.findUnique({ where: { username } });

  if (!user || !verifyPassword(password, user.passwordHash)) {
    return NextResponse.json({ error: "Invalid username or password" }, { status: 401 });
  }

  await createSession(user);
  return NextResponse.json({ ok: true, user: { id: user.id, username: user.username, role: user.role } });
}