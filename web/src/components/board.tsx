"use client";

import { useCallback, useEffect, useState } from "react";
import Link from "next/link";
import { ges } from "@/lib/format";

type Row = {
  governance: string;
  lifecycle: string;
  title: string;
  description: string | null;
  department: string;
  category: string;
  budgetCap: string;
  numberOfProposals: string;
  proposalDeadline: string;
  votingDeadline: string;
  awardDeadline: string;
  createdAt: string;
  shortlistCompanies: string[];
  mine: boolean;
};

const LIFECYCLE_COLORS: Record<string, string> = {
  CREATED: "bg-zinc-300 text-zinc-800",
  PROPOSAL: "bg-sky-500 text-white",
  VOTING: "bg-amber-500 text-white",
  DELIBERATION: "bg-violet-500 text-white",
  AWARDED: "bg-emerald-500 text-white",
  COMPLETE: "bg-emerald-700 text-white",
  CANCELLED: "bg-red-600 text-white",
};

const LIFECYCLE_BORDERS: Record<string, string> = {
  CREATED: "border-zinc-300",
  PROPOSAL: "border-sky-500",
  VOTING: "border-amber-500",
  DELIBERATION: "border-violet-500",
  AWARDED: "border-emerald-500",
  COMPLETE: "border-emerald-700",
  CANCELLED: "border-red-600",
};

// Relevance order for the board: live tenders first, finished last.
const LIFECYCLE_ORDER: Record<string, number> = {
  PROPOSAL: 0,
  VOTING: 1,
  DELIBERATION: 2,
  AWARDED: 3,
  CANCELLED: 4,
  COMPLETE: 5,
};

const FILTERS: { label: string; value: string | null }[] = [
  { label: "All", value: null },
  { label: "Bidding open", value: "PROPOSAL" },
  { label: "Voting", value: "VOTING" },
  { label: "Deliberation", value: "DELIBERATION" },
  { label: "Awarded", value: "AWARDED" },
  { label: "Complete", value: "COMPLETE" },
  { label: "Cancelled", value: "CANCELLED" },
];

function fmtDeadline(ts: string) {
  const d = new Date(Number(ts) * 1000);
  return d.toLocaleString([], { month: "short", day: "numeric", hour: "2-digit", minute: "2-digit" });
}

export default function Board() {
  const [rows, setRows] = useState<Row[]>([]);
  const [loading, setLoading] = useState(true);
  const [isCommittee, setIsCommittee] = useState(false);
  const [role, setRole] = useState<string | null>(null);
  const [shortlistSizes, setShortlistSizes] = useState<Record<string, string>>({});
  const [error, setError] = useState("");
  const [busyFor, setBusyFor] = useState<string | null>(null);
  const [now, setNow] = useState(() => Date.now() / 1000);
  const [filter, setFilter] = useState<string | null>(null);
  const [budgetFilter, setBudgetFilter] = useState<{ min: string; max: string }>({ min: "", max: "" });

// Tenders sorted by relevance (live first, finished last). CREATED tenders
// are internal drafts: hidden from everyone except the committee, who must
// accept them to open bidding.
  const visible = rows
    .filter((r) => (isCommittee ? true : r.lifecycle !== "CREATED"))
    .filter((r) => (filter ? r.lifecycle === filter : true))
    .filter((r) => {
      const budget = Number(r.budgetCap);
      if (budgetFilter.min && budget < Number(budgetFilter.min)) return false;
      if (budgetFilter.max && budget > Number(budgetFilter.max)) return false;
      return true;
    })
    .sort((a, b) => {
      const byLifecycle = (LIFECYCLE_ORDER[a.lifecycle] ?? 99) - (LIFECYCLE_ORDER[b.lifecycle] ?? 99);
      if (byLifecycle !== 0) return byLifecycle;
      return Number(b.createdAt ?? 0) - Number(a.createdAt ?? 0);
    });

  const load = useCallback(() => {
    fetch("/api/projects")
      .then((r) => r.json())
      .then((d) => setRows(d.projects))
      .catch(() => {})
      .finally(() => setLoading(false));
    fetch("/api/auth/me")
      .then((r) => r.json())
      .then((m) => {
        setIsCommittee(m.user?.role === "committee");
        setRole(m.user?.role ?? null);
      })
      .catch(() => {});
  }, []);

  useEffect(() => {
    load();
    const t = setInterval(load, 8000);
    return () => clearInterval(t);
  }, [load]);

  useEffect(() => {
    const t = setInterval(() => setNow(Date.now() / 1000), 8000);
    return () => clearInterval(t);
  }, []);

  async function act(row: Row, action: string) {
    setBusyFor(row.governance);
    setError("");
    const body: Record<string, unknown> = { action };
    if (action === "closeVoting") {
      body.shortlistSize = Number(shortlistSizes[row.governance] ?? 1);
    }
    const res = await fetch(`/api/project/${row.governance}/lifecycle`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(body),
    });
    const data = await res.json();
    setBusyFor(null);
    if (!res.ok) setError(data.error ?? "Action failed");
    load();
  }

  // Which lifecycle actions are due right now, per lifecycle.
  function dueAction(row: Row): { action: string; label: string } | null {
    switch (row.lifecycle) {
      case "CREATED":
        return { action: "acceptProposals", label: "Accept proposals" };
      case "PROPOSAL":
        if (now >= Number(row.proposalDeadline)) return { action: "openVoting", label: "Open voting" };
        return null;
      case "VOTING":
        if (now >= Number(row.votingDeadline)) return { action: "closeVoting", label: "Close voting" };
        return null;
      case "DELIBERATION":
        if (now > Number(row.awardDeadline)) return { action: "expire", label: "Expire" };
        return null;
      default:
        return null;
    }
  }

  function renderCard(r: Row) {
    const due = isCommittee ? dueAction(r) : null;
    return (
      <div
        key={r.governance}
        className={`border rounded-xl transition-transform duration-150 hover:scale-[1.01] hover:shadow-lg hover:shadow-zinc-950/60 ${
          LIFECYCLE_BORDERS[r.lifecycle] ?? "border-zinc-200"
        }`}
      >
        <Link href={`/projects/${r.governance}`} className="block p-5">
          <div className="flex items-center justify-between gap-4">
            <div>
              <div className="flex items-center gap-3">
                <span
                  className={`px-2 py-0.5 rounded-full text-xs font-medium ${LIFECYCLE_COLORS[r.lifecycle] ?? "bg-zinc-300"}`}
                >
                  {r.lifecycle}
                </span>
                <h2 className="text-lg font-semibold">{r.title}</h2>
              </div>
              <p className="text-sm text-zinc-500 mt-1">
                {r.department} · {r.category} · {r.numberOfProposals} bids · budget {ges(r.budgetCap)}
              </p>
              {r.description && (
                <p className="text-sm text-zinc-500 mt-2 line-clamp-2">{r.description}</p>
              )}
              {["DELIBERATION", "AWARDED", "COMPLETE", "CANCELLED"].includes(r.lifecycle) &&
                r.shortlistCompanies.length > 0 && (
                  <div className="flex flex-wrap items-center gap-2 mt-3">
                    <span className="text-xs text-zinc-500 uppercase tracking-widest">Shortlist:</span>
                    {r.shortlistCompanies.map((name) => (
                      <span
                        key={name}
                        className="px-2.5 py-1 rounded-full text-xs font-medium bg-violet-500/15 text-violet-600 border border-violet-700"
                      >
                        {name}
                      </span>
                    ))}
                  </div>
                )}
            </div>
            <div className="text-right text-xs text-zinc-500">
              <div>
                {Number(r.proposalDeadline) < now
                  ? "Proposals closed"
                  : "Proposals close"}{" "}
                {fmtDeadline(r.proposalDeadline)}
              </div>
              <div>
                {Number(r.votingDeadline) < now ? "Voting closed" : "Voting closes"}{" "}
                {fmtDeadline(r.votingDeadline)}
              </div>
            </div>
          </div>
        </Link>

        {due && (
          <div className="border-t border-zinc-200 px-5 py-3 flex items-center gap-3">
            <span className="text-xs text-zinc-500 uppercase tracking-widest">Due:</span>
            {due.action === "closeVoting" && (
              <div className="flex items-center gap-2">
                <span className="text-xs text-zinc-500">Shortlist size</span>
                <input
                  type="number"
                  min="1"
                  value={shortlistSizes[r.governance] ?? "1"}
                  onChange={(e) =>
                    setShortlistSizes((s) => ({ ...s, [r.governance]: e.target.value }))
                  }
                  className="bg-white border border-zinc-300 rounded px-2 py-1 w-16 text-sm"
                />
              </div>
            )}
            <button
              disabled={busyFor === r.governance}
              onClick={() => act(r, due.action)}
              className="bg-emerald-600 text-white font-medium rounded-md px-3 py-1.5 text-sm hover:bg-emerald-500 disabled:opacity-50"
            >
              {busyFor === r.governance ? "Working…" : due.label}
            </button>
            <span className="text-xs text-zinc-500">from the board</span>
          </div>
        )}
      </div>
    );
  }

  return (
    <div>
      <div className="mb-8 flex items-center justify-between">
        <div>
          <h1 className="text-3xl font-bold tracking-tight">Tender Board</h1>
          <p className="text-zinc-500 mt-1">
            Public tenders on Arbitrum Sepolia. Every vote, award, and payment is verifiable on-chain.
          </p>
        </div>
        {isCommittee && (
          <Link
            href="/create"
            className="bg-emerald-600 text-white font-medium rounded-lg px-5 py-2.5 hover:bg-emerald-500 transition shrink-0"
          >
            New Tender
          </Link>
        )}
      </div>

      {error && (
        <div className="flex items-start justify-between gap-3 border border-red-200 bg-red-50 rounded-xl px-4 py-3 mb-4">
          <p className="text-red-500 text-sm">{error}</p>
          <button onClick={() => setError("")} className="text-red-600 hover:text-red-500 text-sm" aria-label="Dismiss">
            ✕
          </button>
        </div>
      )}

      {/* Filters */}
      <div className="flex flex-wrap items-center gap-2 mb-6">
        {FILTERS.map((f) => (
          <button
            key={f.label}
            type="button"
            onClick={() => setFilter(f.value)}
            className={`px-3 py-1.5 rounded-full text-sm font-medium border transition ${
              filter === f.value
                ? "bg-emerald-600 text-white border-emerald-600"
                : "bg-white text-zinc-700 border-zinc-300 hover:border-emerald-600 hover:text-emerald-700"
            }`}
          >
            {f.label}
          </button>
        ))}
        <div className="flex items-center gap-2 ml-auto">
          <span className="text-sm text-zinc-500">Budget</span>
          <input
            type="number"
            min="0"
            placeholder="Min"
            value={budgetFilter.min}
            onChange={(e) => setBudgetFilter((b) => ({ ...b, min: e.target.value }))}
            className="bg-white border border-zinc-300 rounded px-2 py-1.5 w-24 text-sm"
          />
          <span className="text-zinc-500">–</span>
          <input
            type="number"
            min="0"
            placeholder="Max"
            value={budgetFilter.max}
            onChange={(e) => setBudgetFilter((b) => ({ ...b, max: e.target.value }))}
            className="bg-white border border-zinc-300 rounded px-2 py-1.5 w-24 text-sm"
          />
        </div>
      </div>

      {loading ? (
        <p className="text-zinc-500">Loading tenders…</p>
      ) : visible.length === 0 ? (
        <div className="border border-dashed border-zinc-300 rounded-xl p-12 text-center text-zinc-500">
          {rows.length === 0
            ? "No tenders yet. Sign up as the committee and create the first one."
            : "No tenders match the current filters."}
        </div>
      ) : (
        <div className="grid gap-6">
          {visible.some((r) => r.mine) && (
            <div>
              <h2 className="text-sm font-semibold text-zinc-500 mb-3">
                {role === "company"
                  ? "Your projects"
                  : role === "committee"
                    ? "Current tenders"
                    : "Your committees"}
              </h2>
              <div className="grid gap-4">
                {visible
                  .filter((r) => r.mine)
                  .map((r) => renderCard(r))}
              </div>
              <div className="my-6 border-t border-zinc-200" />
              <h2 className="text-sm font-semibold text-zinc-500 mb-3">Open tenders</h2>
            </div>
          )}
          <div className="grid gap-4">
            {visible
              .filter((r) => !r.mine)
              .map((r) => renderCard(r))}
          </div>
        </div>
      )}
    </div>
  );
}