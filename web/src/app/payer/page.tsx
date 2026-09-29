"use client";

import { useCallback, useEffect, useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { ges } from "@/lib/format";

type Receipt = {
  tokenId: string;
  redeemer: string;
  redeemerName: string;
  escrow: string;
  projectName: string;
  governance: string | null;
  amount: string;
  destinationId: string;
  state: "Pending" | "Paid" | "Rejected";
  payoutRef: string;
};

function shortAddr(a: string) {
  return a ? `${a.slice(0, 6)}…${a.slice(-4)}` : "—";
}

const STATE_COLORS: Record<string, string> = {
  Pending: "bg-amber-500 text-white",
  Paid: "bg-emerald-600 text-white",
  Rejected: "bg-red-600 text-white",
};

export default function PayerDashboard() {
  const router = useRouter();
  const [me, setMe] = useState<{ user: { username: string; role: string } | null } | null>(null);
  const [receipts, setReceipts] = useState<Receipt[]>([]);
  const [selected, setSelected] = useState<Receipt | null>(null);
  const [decision, setDecision] = useState<"accepted" | "rejected">("accepted");
  const [payoutRef, setPayoutRef] = useState("");
  const [proofFile, setProofFile] = useState<File | null>(null);
  const [reason, setReason] = useState("");
  const [error, setError] = useState("");
  const [busy, setBusy] = useState(false);

  const load = useCallback(async () => {
    const [m, r] = await Promise.all([
      fetch("/api/auth/me").then((x) => x.json()),
      fetch("/api/payer/receipts").then((x) => x.json()),
    ]);
    setMe(m);
    setReceipts(r.receipts ?? []);
  }, []);

  useEffect(() => {
    load();
    const t = setInterval(load, 8000);
    return () => clearInterval(t);
  }, [load]);

  if (!me) return <p className="text-zinc-500">Loading…</p>;
  if (!me.user || me.user.role !== "payer") {
    router.push("/");
    return null;
  }

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    if (!selected) return;
    setBusy(true);
    setError("");
    const form = new FormData();
    form.set("tokenId", selected.tokenId);
    form.set("decision", decision);
    if (decision === "accepted") {
      form.set("payoutRef", payoutRef);
      if (proofFile) form.set("proofFile", proofFile);
    } else {
      form.set("reason", reason);
    }
    const res = await fetch("/api/payer/decide", { method: "POST", body: form });
    const data = await res.json();
    setBusy(false);
    if (!res.ok) return setError(data.error ?? "Decision failed");
    setSelected(null);
    setPayoutRef("");
    setProofFile(null);
    setReason("");
    await load();
  }

  const pending = receipts.filter((r) => r.state === "Pending");

  return (
    <div className="max-w-4xl mx-auto">
      <Link href="/" className="text-sm text-zinc-500 hover:text-emerald-600 inline-block mb-4">
        ← Back to tender board
      </Link>
      <div className="mb-8">
        <h1 className="text-3xl font-bold tracking-tight">Payments</h1>
        <p className="text-zinc-500 mt-1">
          As the paying authority you certify off-ramp redemptions: confirm the fiat payout was made
          (with proof of payment) or reject the request with a reason. Every decision is recorded
          on-chain.
        </p>
      </div>

      {error && (
        <div className="flex items-start justify-between gap-3 border border-red-200 bg-red-50 rounded-xl px-4 py-3 mb-4">
          <p className="text-red-500 text-sm">{error}</p>
          <button onClick={() => setError("")} className="text-red-600 hover:text-red-500 text-sm" aria-label="Dismiss">
            ✕
          </button>
        </div>
      )}

      <div className="grid lg:grid-cols-2 gap-6">
        {/* Pending queue */}
        <div className="border border-zinc-200 rounded-xl p-5">
          <h2 className="font-semibold mb-1">Redemption queue</h2>
          <p className="text-xs text-zinc-500 mb-4">
            {pending.length} pending · {receipts.filter((r) => r.state === "Paid").length} paid ·{" "}
            {receipts.filter((r) => r.state === "Rejected").length} rejected
          </p>
          {pending.length === 0 ? (
            <p className="text-zinc-500 text-sm">No pending redemptions right now.</p>
          ) : (
            <div className="grid gap-2">
              {pending.map((r) => (
                <button
                  key={r.tokenId}
                  onClick={() => {
                    setSelected(r);
                    setDecision("accepted");
                  }}
                  className={`text-left border rounded-lg p-3 transition ${
                    selected?.tokenId === r.tokenId
                      ? "border-emerald-600 bg-emerald-500/5"
                      : "border-zinc-200 hover:border-zinc-300"
                  }`}
                >
                  <div className="flex items-center justify-between">
                    <span className="font-medium">Receipt #{r.tokenId}</span>
                    <span className={`px-2 py-0.5 rounded-full text-xs font-medium ${STATE_COLORS[r.state]}`}>
                      {r.state}
                    </span>
                  </div>
                  <p className="text-sm text-zinc-500 mt-1">
                    {ges(r.amount)} · from {r.redeemerName}
                    {r.governance && (
                      <>
                        {" "}· {r.projectName}
                      </>
                    )}
                  </p>
                </button>
              ))}
            </div>
          )}

          {receipts.filter((r) => r.state !== "Pending").length > 0 && (
            <div className="mt-6">
              <h3 className="text-xs uppercase tracking-widest text-zinc-500 font-semibold mb-2">History</h3>
              <div className="grid gap-2">
                {receipts
                  .filter((r) => r.state !== "Pending")
                  .map((r) => (
                    <div key={r.tokenId} className="border border-zinc-200 rounded-lg p-3">
                      <div className="flex items-center justify-between">
                        <span className="font-medium text-sm">Receipt #{r.tokenId}</span>
                        <span className={`px-2 py-0.5 rounded-full text-xs font-medium ${STATE_COLORS[r.state]}`}>
                          {r.state}
                        </span>
                      </div>
                      <p className="text-xs text-zinc-500 mt-1">
                        {ges(r.amount)} · {r.state === "Paid" ? `ref ${r.payoutRef}` : "rejected"}
                      </p>
                    </div>
                  ))}
              </div>
            </div>
          )}
        </div>

        {/* Decision form */}
        <div className="border border-zinc-200 rounded-xl p-5 h-fit">
          <h2 className="font-semibold mb-4">
            {selected ? `Review receipt #${selected.tokenId}` : "Review a redemption"}
          </h2>

          {!selected ? (
            <p className="text-zinc-500 text-sm">
              Pick a pending redemption from the queue to review it.
            </p>
          ) : (
            <form onSubmit={submit} className="grid gap-4">
              <div className="text-sm text-zinc-500 grid gap-1">
                <p>
                  Redeemer <span className="text-zinc-800 font-medium">{selected.redeemerName}</span>
                </p>
                <p>
                  Amount <span className="text-zinc-800 font-medium">{ges(selected.amount)}</span>
                </p>
                {selected.governance ? (
                  <p>
                    Project <span className="text-zinc-800 font-medium">{selected.projectName}</span>
                  </p>
                ) : (
                  <p>
                    Provenance <span className="text-zinc-800 font-mono">{shortAddr(selected.escrow)}</span>
                  </p>
                )}
              </div>

              <div className="grid grid-cols-2 gap-3">
                <button
                  type="button"
                  onClick={() => setDecision("accepted")}
                  className={`rounded-lg px-4 py-2.5 font-medium text-sm border transition ${
                    decision === "accepted"
                      ? "bg-emerald-600 text-white border-emerald-500"
                      : "border-zinc-300 text-zinc-700 hover:border-emerald-600"
                  }`}
                >
                  Accepted
                </button>
                <button
                  type="button"
                  onClick={() => setDecision("rejected")}
                  className={`rounded-lg px-4 py-2.5 font-medium text-sm border transition ${
                    decision === "rejected"
                      ? "bg-red-600 text-white border-red-600"
                      : "border-zinc-300 text-zinc-700 hover:border-red-600"
                  }`}
                >
                  Rejected
                </button>
              </div>

              {decision === "accepted" ? (
                <>
                  <label className="grid gap-1">
                    <span className="text-sm text-zinc-500">
                      Payment reference <span className="text-zinc-500 text-xs">your bank/payout reference</span>
                    </span>
                    <input
                      value={payoutRef}
                      onChange={(e) => setPayoutRef(e.target.value)}
                      className="bg-white border border-zinc-300 rounded-lg px-4 py-2.5"
                      placeholder="e.g. POP-2026-0912"
                      required
                    />
                  </label>
                  <label className="grid gap-1">
                    <span className="text-sm text-zinc-500">
                      Proof of payment <span className="text-zinc-500 text-xs">bank statement / POP document</span>
                    </span>
                    {proofFile ? (
                      <div className="flex items-center justify-between bg-white border border-zinc-300 rounded-lg px-4 py-2.5 text-sm">
                        <span className="text-zinc-700 truncate">{proofFile.name}</span>
                        <button type="button" onClick={() => setProofFile(null)} className="text-zinc-500 hover:text-red-600 shrink-0 ml-3">
                          Remove ✕
                        </button>
                      </div>
                    ) : (
                      <input
                        type="file"
                        className="bg-white border border-zinc-300 rounded-lg px-4 py-2.5 text-sm"
                        onChange={(e) => setProofFile(e.target.files?.[0] ?? null)}
                        required
                      />
                    )}
                  </label>
                </>
              ) : (
                <label className="grid gap-1">
                  <span className="text-sm text-zinc-500">
                    Reason for rejection <span className="text-zinc-500 text-xs">recorded on-chain</span>
                  </span>
                  <textarea
                    value={reason}
                    onChange={(e) => setReason(e.target.value)}
                    className="bg-white border border-zinc-300 rounded-lg px-4 py-2.5 min-h-20"
                    placeholder="e.g. Destination details don't match the KYC records on file."
                    required
                  />
                </label>
              )}

              <button
                disabled={busy}
                className={`font-medium rounded-lg py-2.5 disabled:opacity-50 ${
                  decision === "accepted"
                    ? "bg-emerald-600 text-white hover:bg-emerald-500"
                    : "bg-red-600 text-white hover:bg-red-600"
                }`}
              >
                {busy ? "Recording on-chain…" : decision === "accepted" ? "Confirm payment" : "Reject redemption"}
              </button>
              <p className="text-xs text-zinc-500">
                The decision is a real on-chain transaction from the payer wallet — it can&apos;t be
                undone.
              </p>
            </form>
          )}
        </div>
      </div>
    </div>
  );
}