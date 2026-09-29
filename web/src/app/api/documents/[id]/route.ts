import { NextResponse } from "next/server";

// GET /api/documents/[id] - raw bytes of a stored document (spec, image, evidence)
export async function GET(_req: Request, { params }: { params: Promise<{ id: string }> }) {
  try {
    const { id } = await params;
    const { prisma } = await import("@/lib/db");
    const doc = await prisma.document.findUnique({ where: { id: Number(id) } });
    if (!doc) return NextResponse.json({ error: "Document not found" }, { status: 404 });
    return new NextResponse(new Uint8Array(doc.data), {
      headers: {
        "content-type": doc.mimeType || "application/octet-stream",
        "content-disposition": `inline; filename="${doc.fileName}"`,
        "cache-control": "public, max-age=31536000, immutable",
      },
    });
  } catch {
    return NextResponse.json({ error: "Document not found" }, { status: 404 });
  }
}