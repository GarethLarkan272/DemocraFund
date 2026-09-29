import { SignJWT, jwtVerify } from "jose";
import { cookies } from "next/headers";

const secret = new TextEncoder().encode(process.env.SESSION_SECRET ?? "dev-session-secret");

export type Session = {
  userId: number;
  username: string;
  role: string;
};

export async function createSession(user: { id: number; username: string; role: string }) {
  const token = await new SignJWT({
    userId: user.id,
    username: user.username,
    role: user.role,
  })
    .setProtectedHeader({ alg: "HS256" })
    .setIssuedAt()
    .setExpirationTime("7d")
    .sign(secret);

  (await cookies()).set("df_session", token, {
    httpOnly: true,
    sameSite: "lax",
    path: "/",
    maxAge: 60 * 60 * 24 * 7,
  });
}

export async function getSession(): Promise<Session | null> {
  const token = (await cookies()).get("df_session")?.value;
  if (!token) return null;
  try {
    const { payload } = await jwtVerify(token, secret);
    return {
      userId: payload.userId as number,
      username: payload.username as string,
      role: payload.role as string,
    };
  } catch {
    return null;
  }
}

export async function destroySession() {
  (await cookies()).delete("df_session");
}