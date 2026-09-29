import { NextResponse } from "next/server";
import { prisma } from "@/lib/db";

// GET /api/project/[governance]/documents?proposalId=N
// Tender docs & images by default; proposal documents when proposalId is given.
export async function GET(req: Request, { params }: { params: Promise<{ governance: string }> }) {
  try {
    const { governance } = await params;
    const { searchParams } = new URL(req.url);
    const proposalId = searchParams.get("proposalId");

    const docs = await prisma.document.findMany({
      where: {
        project: { governance: governance.toLowerCase() },
        kind: proposalId ? "proposal" : "tender",
        ...(proposalId ? { proposal: { proposalId: Number(proposalId) } } : {}),
      },
      select: { id: true, fileName: true, mimeType: true, contentHash: true },
      orderBy: { uploadedAt: "asc" },
    });
    return NextResponse.json({ documents: docs });
  } catch {
    return NextResponse.json({ documents: [] });
  }
}