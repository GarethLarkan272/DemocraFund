"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import { useParams } from "next/navigation";
import Link from "next/link";
import { ges } from "@/lib/format";

type Proposal = {
  id: string;
  cost: string;
  admin: string;
  fundWallet: string;
  specContentHash: string;
  depositRequired: boolean;
  companyName: string | null;
  milestones: string[];
  votes: string;
};

type Milestone = { amount: string; evidenceHash: string; released: boolean };

type TenderDoc = { id: number; fileName: string; mimeType: string; contentHash: string };

type Project = {
  address: string;
  lifecycle: string;
  title: string;
  description: string | null;
  department: string;
  category: string;
  budgetCap: string;
  committeeFeePerSignature: string;
  proposalDeadline: string;
  votingDeadline: string;
  awardDeadline: string;
  numberOfProposals: string;
  numberOfShortlistedProjects: string;
  winningProposalId: string;
  safeWallet: string;
  treasuryWallet: string;
  optedInCount: string;
  selectionPending: boolean;
  selectionRequestedAt: string;
  committeeMembers: string[];
  alternates: string[];
  shortlist: string[];
  proposals: Proposal[];
  escrow: {
    address: string;
    totalProjectBudget: string;
    feeReserve: string;
    totalReleased: string;
    balance: string;
    currentMilestoneIndex: string;
    cancelled: boolean;
    committeeFinalized: boolean;
    builderSigner: string;
    memberSigners: string[];
    alternates: string[];
    milestones: Milestone[];
    totalUncollectedFees: string;
  } | null;
};

const LIFECYCLE_COLORS: Record<string, string> = {
  CREATED: "bg-zinc-300",
  PROPOSAL: "bg-sky-500",
  VOTING: "bg-amber-500",
  DELIBERATION: "bg-violet-500",
  AWARDED: "bg-emerald-500",
  COMPLETE: "bg-emerald-700",
  CANCELLED: "bg-red-600",
};

const LIFECYCLE_ACTIONS: Record<string, { action: string; label: string }[]> = {
  CREATED: [{ action: "acceptProposals", label: "Accept proposals" }],
  PROPOSAL: [{ action: "openVoting", label: "Close bidding, open voting" }],
  VOTING: [{ action: "closeVoting", label: "Close voting, fix shortlist" }],
  DELIBERATION: [],
  AWARDED: [],
  COMPLETE: [],
  CANCELLED: [],
};

function shortAddr(a: string) {
  return a ? `${a.slice(0, 6)}…${a.slice(-4)}` : "—";
}

function deadline(ts: string) {
  return new Date(Number(ts) * 1000).toLocaleString([], {
    month: "short",
    day: "numeric",
    hour: "2-digit",
    minute: "2-digit",
  });
}

export default function ProjectPage() {
  const params = useParams<{ governance: string }>();
  const governance = params.governance;

  const [project, setProject] = useState<Project | null>(null);
  const [documents, setDocuments] = useState<TenderDoc[]>([]);
  const [expandedBid, setExpandedBid] = useState<string | null>(null);
  const [proposalDocs, setProposalDocs] = useState<Record<string, TenderDoc[]>>({});
  const [meOptedIn, setMeOptedIn] = useState(false);
  const [meVoted, setMeVoted] = useState(false);
  const [confirmVote, setConfirmVote] = useState<string | null>(null);
  const [now, setNow] = useState(() => Date.now() / 1000);
  const [tab, setTab] = useState<"info" | "progress">("info");
  const [memberNames, setMemberNames] = useState<Record<string, string | null>>({});
  const [meSigned, setMeSigned] = useState<boolean[]>([]);
  const [sigCounts, setSigCounts] = useState<number[]>([]);
  const [me, setMe] = useState<{ user: { username: string; role: string } | null; wallet?: string } | null>(null);
  const [error, setError] = useState("");
  const [busy, setBusy] = useState(false);
  const [shortlistSize, setShortlistSize] = useState("1");
  const [extendDays, setExtendDays] = useState("7");
  const [confirmCancel, setConfirmCancel] = useState(false);
  const [reason, setReason] = useState("");
  const [evidenceFile, setEvidenceFile] = useState<File | null>(null);
  const [bidOpen, setBidOpen] = useState(false);
  const [bidCost, setBidCost] = useState("");
  const [bidMilestones, setBidMilestones] = useState<string[]>(["", ""]);
  const [bidDeposit, setBidDeposit] = useState(false);
  const [bidFile, setBidFile] = useState<File | null>(null);

  const load = useCallback(async () => {
    const [p, d, m] = await Promise.all([
      fetch(`/api/project/${governance}`).then((r) => r.json()),
      fetch(`/api/project/${governance}/documents`).then((r) => r.json()),
      fetch("/api/auth/me").then((r) => r.json()),
    ]);
    if (p.project) setProject(p.project);
    if (d.documents) setDocuments(d.documents);
    setMemberNames(p.memberNames ?? {});
    setMeOptedIn(!!p.meOptedIn);
    setMeVoted(!!p.meVoted);
    setMeSigned(p.meSigned ?? []);
    setSigCounts(p.sigCounts ?? []);
    setMe(m);
  }, [governance]);

  useEffect(() => {
    load();
    const t = setInterval(load, 8000);
    return () => clearInterval(t);
  }, [load]);

  useEffect(() => {
    const t = setInterval(() => setNow(Date.now() / 1000), 8000);
    return () => clearInterval(t);
  }, []);

  async function act(body: Record<string, unknown>) {
    setBusy(true);
    setError("");
    const res = await fetch(`/api/project/${governance}/lifecycle`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(body),
    });
    const data = await res.json();
    setBusy(false);
    if (!res.ok) setError(data.error ?? "Transaction failed");
    await load();
  }

  async function vote(proposalId: string) {
    setConfirmVote(null);
    setBusy(true);
    setError("");
    const res = await fetch(`/api/project/${governance}/vote`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ proposalId }),
    });
    const data = await res.json();
    setBusy(false);
    if (!res.ok) setError(data.error ?? "Vote failed");
    await load();
  }

  async function requestVote(proposalId: string) {
    if (meVoted) return;
    setConfirmVote(proposalId);
  }

  async function optin() {
    setBusy(true);
    setError("");
    const res = await fetch(`/api/project/${governance}/optin`, { method: "POST" });
    const data = await res.json();
    setBusy(false);
    if (!res.ok) setError(data.error ?? "Opt-in failed");
    await load();
  }

  async function approveMilestone(index?: number) {
    setBusy(true);
    setError("");
    const res = await fetch(`/api/project/${governance}/milestone`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ action: "approve", milestoneIndex: index }),
    });
    const data = await res.json();
    setBusy(false);
    if (!res.ok) setError(data.error ?? "Approval failed");
    await load();
  }

  async function submitEvidence() {
    setBusy(true);
    setError("");
    const form = new FormData();
    form.set("action", "submit");
    form.set("milestoneIndex", project?.escrow?.currentMilestoneIndex ?? "0");
    if (evidenceFile) form.set("evidenceFile", evidenceFile);
    const res = await fetch(`/api/project/${governance}/milestone`, { method: "POST", body: form });
    const data = await res.json();
    setBusy(false);
    if (!res.ok) setError(data.error ?? "Submission failed");
    await load();
  }

  async function collectFees() {
    setBusy(true);
    setError("");
    const res = await fetch(`/api/project/${governance}/fees`, { method: "POST" });
    const data = await res.json();
    setBusy(false);
    if (!res.ok) setError(data.error ?? "Collection failed");
    await load();
  }

  async function signCancellation() {
    setBusy(true);
    setError("");
    const res = await fetch(`/api/project/${governance}/cancel`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ reason }),
    });
    const data = await res.json();
    setBusy(false);
    if (!res.ok) setError(data.error ?? "Cancellation signature failed");
    await load();
  }

  async function submitBid() {
    setBusy(true);
    setError("");
    const form = new FormData();
    form.set("cost", bidCost);
    form.set("milestones", JSON.stringify(bidMilestones.map((m) => m.trim()).filter(Boolean)));
    form.set("depositRequired", String(bidDeposit));
    if (bidFile) form.set("specFile", bidFile);
    const res = await fetch(`/api/project/${governance}/proposal`, { method: "POST", body: form });
    const data = await res.json();
    setBusy(false);
    if (!res.ok) return setError(data.error ?? "Bid failed");
    setBidOpen(false);
    await load();
  }

  async function toggleBid(id: string) {
    setExpandedBid(expandedBid === id ? null : id);
    if (!proposalDocs[id]) {
      const r = await fetch(`/api/project/${governance}/documents?proposalId=${id}`).then((r) => r.json());
      if (r.documents) setProposalDocs((prev) => ({ ...prev, [id]: r.documents }));
    }
  }

  if (!project) return <p className="text-zinc-500">Loading tender…</p>;

  const role = me?.user?.role;
  const wallet = me?.wallet?.toLowerCase();
  const isCommittee = role === "committee";
  const isSigner =
    wallet &&
    (wallet === project.safeWallet.toLowerCase() ||
      project.escrow?.memberSigners.some((m) => m.toLowerCase() === wallet));
  const currentMilestoneIndex = Number(project.escrow?.currentMilestoneIndex ?? 0);
  const current = project.escrow?.milestones[currentMilestoneIndex];
  const memberCount = project.escrow?.memberSigners.length ?? 0;
  // Release needs admin+builder+(≥1 member when members exist): 2-of-2 fallback
  // without members, otherwise 3 minimum (all of admin+builder+one member).
  const releaseRequired = memberCount === 0 ? 2 : 3;
  const evidenceSubmitted = current && current.evidenceHash !== "0x0000000000000000000000000000000000000000000000000000000000000000";
  const myProposal = project.proposals.find((p) => p.admin.toLowerCase() === wallet);

  return (
    <div className="grid gap-6">
      <Link href="/" className="text-sm text-zinc-500 hover:text-emerald-600">
        ← Back to tender board
      </Link>
      {/* Header */}
      <div className="flex items-start justify-between gap-4">
        <div>
          <div className="flex items-center gap-3">
            <span className={`px-2 py-0.5 rounded-full text-xs font-medium ${LIFECYCLE_COLORS[project.lifecycle]}`}>
              {project.lifecycle}
            </span>
            {project.selectionPending && (
              <span className="px-2 py-0.5 rounded-full text-xs font-medium bg-fuchsia-600 animate-pulse">
                Committee draw in progress…
              </span>
            )}
            <h1 className="text-3xl font-bold">{project.title}</h1>
          </div>
          <p className="text-zinc-500 mt-1">
            {project.department} · {project.category} · budget {ges(project.budgetCap)} · fee{" "}
            {ges(project.committeeFeePerSignature)}/sig
          </p>
          <p className="text-xs text-zinc-500 mt-1">
            <a className="underline hover:text-emerald-600" href={`https://sepolia.arbiscan.io/address/${project.address}`} target="_blank">
              View governance on Arbiscan
            </a>
          </p>
        </div>
        <div className="text-right text-xs text-zinc-500">
          <div>
            {Number(project.proposalDeadline) < now ? "Proposals closed" : "Proposals close"}{" "}
            {deadline(project.proposalDeadline)}
          </div>
          <div>
            {Number(project.votingDeadline) < now ? "Voting closed" : "Voting closes"}{" "}
            {deadline(project.votingDeadline)}
          </div>
          {Number(project.awardDeadline) > 0 && (
            <div>
              {Number(project.awardDeadline) < now ? "Award deadline passed" : "Award deadline"}{" "}
              {deadline(project.awardDeadline)}
            </div>
          )}
          <div>{project.optedInCount} members in the committee pool</div>
        </div>
      </div>

      {project.escrow && (
        <div className="flex gap-2 border-b border-zinc-200">
          <button
            onClick={() => setTab("info")}
            className={`px-4 py-2 text-sm font-medium border-b-2 -mb-px transition ${
              tab === "info"
                ? "border-emerald-500 text-emerald-600"
                : "border-transparent text-zinc-500 hover:text-zinc-700"
            }`}
          >
            Info
          </button>
          <button
            onClick={() => setTab("progress")}
            className={`px-4 py-2 text-sm font-medium border-b-2 -mb-px transition ${
              tab === "progress"
                ? "border-emerald-500 text-emerald-600"
                : "border-transparent text-zinc-500 hover:text-zinc-700"
            }`}
          >
            Progress
          </button>
        </div>
      )}

      {project.description && (
        <div className="border border-zinc-200 rounded-xl p-5">
          <h2 className="text-xs uppercase tracking-widest text-zinc-500 font-semibold mb-2">About this tender</h2>
          <p className="text-zinc-700 whitespace-pre-wrap">{project.description}</p>
        </div>
      )}

      {(!project.escrow || tab === "info") && (
        <div className="border border-zinc-200 rounded-xl p-5 grid gap-4">
          <h2 className="text-xs uppercase tracking-widest text-zinc-500 font-semibold">
            Tender documents
          </h2>
          {documents.filter((d) => d.mimeType.startsWith("image/")).length > 0 && (
            <div className="flex flex-wrap gap-3">
              {documents
                .filter((d) => d.mimeType.startsWith("image/"))
                .map((d) => (
                  <a key={d.id} href={`/api/documents/${d.id}`} target="_blank">
                    {/* eslint-disable-next-line @next/next/no-img-element */}
                    <img
                      src={`/api/documents/${d.id}`}
                      alt={d.fileName}
                      className="h-40 w-56 object-cover rounded-lg border border-zinc-300 hover:border-emerald-600 transition"
                    />
                  </a>
                ))}
            </div>
          )}
          {documents
            .filter((d) => !d.mimeType.startsWith("image/"))
            .map((d) => (
              <a
                key={d.id}
                href={`/api/documents/${d.id}`}
                target="_blank"
                className="text-sm text-emerald-600 hover:text-emerald-700 underline"
              >
                📄 {d.fileName} — download the specification
              </a>
            ))}
          <p className="text-xs text-zinc-500">
            Documents are committed on-chain by content hash —{" "}
            {documents.map((d, i) => (
              <span key={d.id}>
                {i > 0 && ", "}
                <code>{d.contentHash.slice(0, 12)}…</code>
              </span>
            ))}
            . View the contract for the full record.
          </p>
        </div>
      )}

      {confirmVote !== null && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-white/80 p-4">
          <div className="border border-zinc-300 rounded-xl bg-white p-6 max-w-sm w-full grid gap-4">
            <div>
              <h3 className="font-semibold text-lg">Confirm your vote</h3>
              <p className="text-zinc-500 text-sm mt-1">
                Your vote is a real, attributable on-chain record — it can&apos;t be changed or
                withdrawn. Cast it for{" "}
                <span className="text-zinc-900 font-medium">
                  {project?.proposals.find((p) => p.id === confirmVote)?.companyName ??
                    `bid #${confirmVote}`}
                </span>
                ?
              </p>
            </div>
            <div className="flex gap-3 justify-end">
              <button
                onClick={() => setConfirmVote(null)}
                className="px-4 py-2 rounded-lg border border-zinc-300 text-sm hover:bg-zinc-100"
              >
                Cancel
              </button>
              <button
                disabled={busy}
                onClick={() => vote(confirmVote)}
                className="bg-amber-500 text-white font-medium rounded-lg px-4 py-2 text-sm hover:bg-amber-500 disabled:opacity-50"
              >
                {busy ? "Casting…" : "Vote"}
              </button>
            </div>
          </div>
        </div>
      )}

      {error && (
        <div className="flex items-start justify-between gap-3 border border-red-200 bg-red-50 rounded-xl px-4 py-3">
          <div className="flex items-start gap-3">
            <span className="mt-0.5 text-red-600">⚠</span>
            <p className="text-red-500 text-sm">{error}</p>
          </div>
          <button
            onClick={() => setError("")}
            className="text-red-600 hover:text-red-500 text-sm leading-none px-1"
            aria-label="Dismiss"
          >
            ✕
          </button>
        </div>
      )}

      {/* Committee lifecycle controls */}
      {(!project.escrow || tab === "progress") && isCommittee && LIFECYCLE_ACTIONS[project.lifecycle] && (
        <div className="border border-zinc-200 rounded-xl p-5">
          <h2 className="font-semibold mb-3">Committee controls</h2>
          <div className="flex flex-wrap items-center gap-3">
            {LIFECYCLE_ACTIONS[project.lifecycle]
              .filter(
                (a) =>
                  !(
                    a.action === "openVoting" &&
                    Number(project.proposalDeadline) < now &&
                    Number(project.numberOfProposals) === 0
                  ),
              )
              .map((a) => (
              <button
                key={a.action}
                disabled={busy}
                onClick={() =>
                  a.action === "closeVoting"
                    ? act({ action: a.action, shortlistSize: Number(shortlistSize) })
                    : act({ action: a.action })
                }
                className="bg-emerald-600 text-white font-medium rounded-lg px-4 py-2 hover:bg-emerald-500 disabled:opacity-50"
              >
                {a.label}
              </button>
            ))}
            {project.lifecycle === "VOTING" && (
              <div className="flex items-center gap-2">
                <span className="text-sm text-zinc-500">Shortlist size</span>
                <input
                  type="number"
                  value={shortlistSize}
                  onChange={(e) => setShortlistSize(e.target.value)}
                  className="bg-white border border-zinc-300 rounded px-2 py-1 w-16"
                />
              </div>
            )}
            {project.lifecycle === "PROPOSAL" &&
              Number(project.proposalDeadline) < now &&
              Number(project.numberOfProposals) === 0 && (
                <>
                  <div className="flex items-center gap-2">
                    <input
                      type="number"
                      min="1"
                      value={extendDays}
                      onChange={(e) => setExtendDays(e.target.value)}
                      className="bg-white border border-zinc-300 rounded px-2 py-2 w-20"
                    />
                    <button
                      disabled={busy}
                      onClick={() => act({ action: "extend", deadlineExtensionDays: Number(extendDays) })}
                      className="bg-sky-500 text-white font-medium rounded-lg px-4 py-2 hover:bg-sky-500 disabled:opacity-50"
                    >
                      Extend deadline (days)
                    </button>
                  </div>
                  {!confirmCancel ? (
                    <button
                      disabled={busy}
                      onClick={() => setConfirmCancel(true)}
                      className="bg-red-600 text-white font-medium rounded-lg px-4 py-2 hover:bg-red-600 disabled:opacity-50"
                    >
                      Cancel tender
                    </button>
                  ) : (
                    <span className="flex items-center gap-2">
                      <span className="text-sm text-zinc-500">
                        No bids were received — cancel this tender permanently?
                      </span>
                      <button
                        disabled={busy}
                        onClick={() => {
                          setConfirmCancel(false);
                          act({ action: "cancel" });
                        }}
                        className="bg-red-600 text-white font-medium rounded-lg px-4 py-2 hover:bg-red-600 disabled:opacity-50"
                      >
                        Confirm cancel
                      </button>
                      <button
                        type="button"
                        disabled={busy}
                        onClick={() => setConfirmCancel(false)}
                        className="bg-zinc-300 text-white font-medium rounded-lg px-4 py-2 hover:bg-zinc-300 disabled:opacity-50"
                      >
                        Keep open
                      </button>
                    </span>
                  )}
                </>
              )}
            {project.lifecycle === "DELIBERATION" &&
              project.shortlist.map((id) => {
                const p = project.proposals.find((x) => x.id === id);
                if (!p) return null;
                return (
                  <button
                    key={p.id}
                    disabled={busy}
                    onClick={() => act({ action: "award", proposalId: Number(p.id) })}
                    className="bg-violet-500 text-white font-medium rounded-lg px-4 py-2 hover:bg-violet-500 disabled:opacity-50"
                    title={`Award proposal #${p.id} (shortlisted: top-${project.numberOfShortlistedProjects} by votes)`}
                  >
                    Award bid #{p.id} — {p.companyName ?? p.id}
                  </button>
                );
              })}
            {project.selectionPending && (
              <button
                disabled={busy}
                onClick={() => act({ action: "retry" })}
                className="bg-zinc-300 text-white font-medium rounded-lg px-4 py-2 hover:bg-zinc-300 disabled:opacity-50"
              >
                Retry draw
              </button>
            )}
            {project.lifecycle === "AWARDED" && project.escrow && (
              <>
                {project.escrow.milestones.every((m) => m.released) && (
                  <button
                    disabled={busy}
                    onClick={() => act({ action: "complete" })}
                    className="bg-emerald-600 text-white font-medium rounded-lg px-4 py-2 hover:bg-emerald-500 disabled:opacity-50"
                  >
                    Complete project
                  </button>
                )}
                <button
                  disabled={busy}
                  onClick={() => act({ action: "expire" })}
                  className="bg-zinc-300 text-white font-medium rounded-lg px-4 py-2 hover:bg-zinc-300 disabled:opacity-50"
                >
                  Expire deliberation
                </button>
              </>
            )}
          </div>
        </div>
      )}

      {/* Proposals */}
      {(!project.escrow || tab === "info") && (
      <div className="border border-zinc-200 rounded-xl p-5">
        <div className="flex items-center justify-between mb-3">
          <h2 className="font-semibold">Proposals ({project.numberOfProposals})</h2>
          {role === "company" && !myProposal && project.lifecycle === "PROPOSAL" && (
            <button
              onClick={() => setBidOpen(!bidOpen)}
              className="bg-sky-500 text-white font-medium rounded-lg px-4 py-2 hover:bg-sky-500"
            >
              Submit a bid
            </button>
          )}
        </div>

        {bidOpen && (
          <div className="border border-zinc-300 rounded-lg p-5 mb-4 grid gap-4 max-w-xl">
            <div>
              <h3 className="font-medium mb-1">Your bid</h3>
              <p className="text-xs text-zinc-500">
                The document you upload is hashed and that hash is committed on-chain — the milestone
                schedule must sum exactly to your price.
              </p>
            </div>
            <label className="grid gap-1">
              <span className="text-sm text-zinc-500">Total cost (Rands)</span>
              <input
                value={bidCost}
                onChange={(e) => setBidCost(e.target.value)}
                className="bg-white border border-zinc-300 rounded px-3 py-2"
                placeholder="e.g. 1000"
                type="number"
                min="1"
                required
              />
            </label>
            <div className="grid gap-2">
              <span className="text-sm text-zinc-500">Milestones</span>
              <div className="grid gap-2">
                {bidMilestones.map((m, i) => (
                  <div key={i} className="grid gap-1">
                    <div
                      className={`flex items-center gap-2 rounded-lg px-3 py-2 border transition ${
                        bidDeposit && i === 0
                          ? "border-emerald-500 bg-emerald-500/10"
                          : "border-transparent"
                      }`}
                    >
                      <span className="text-xs text-zinc-500 w-20 shrink-0">M{i + 1}</span>
                      <input
                        value={m}
                        onChange={(e) => {
                          const next = [...bidMilestones];
                          next[i] = e.target.value;
                          setBidMilestones(next);
                        }}
                        className="bg-white border border-zinc-300 rounded px-3 py-2 flex-1"
                        placeholder="Amount in Rands"
                        type="number"
                        min="0"
                      />
                      <button
                        type="button"
                        onClick={() => setBidMilestones(bidMilestones.filter((_, j) => j !== i))}
                        className="text-zinc-500 hover:text-red-600 text-sm px-2"
                        aria-label={`Remove milestone ${i + 1}`}
                      >
                        ✕
                      </button>
                    </div>
                    {bidDeposit && i === 0 && (
                      <p className="text-xs text-emerald-600 font-medium px-3">
                        This is the deposit amount — released first when the contract is awarded.
                      </p>
                    )}
                  </div>
                ))}
              </div>
              <div className="flex items-center justify-between text-sm">
                <button
                  type="button"
                  onClick={() => setBidMilestones([...bidMilestones, ""])}
                  className="text-emerald-600 hover:text-emerald-700"
                >
                  + Add milestone
                </button>
                <span
                  className={
                    bidMilestones.reduce((s, x) => s + (Number(x) || 0), 0) === Number(bidCost) && bidCost
                      ? "text-emerald-600"
                      : "text-zinc-500"
                  }
                >
                  Sum:{" "}
                  {ges(bidMilestones.reduce((s, x) => s + (Number(x) || 0), 0))}
                  {bidMilestones.reduce((s, x) => s + (Number(x) || 0), 0) === Number(bidCost) && bidCost
                    ? " — matches your price ✓"
                    : bidCost
                      ? " — must equal your price"
                      : ""}
                </span>
              </div>
            </div>
            <label className="flex items-start gap-3 border border-zinc-300 rounded-lg px-3 py-2.5 cursor-pointer">
              <input
                type="checkbox"
                checked={bidDeposit}
                onChange={(e) => setBidDeposit(e.target.checked)}
                className="mt-1 accent-emerald-500"
              />
              <span className="text-sm">
                <span className="text-zinc-800">A deposit is required for this project</span>
                <span className="block text-xs text-zinc-500 mt-0.5">
                  If ticked, milestone 1&apos;s amount is your deposit — released first when the contract is
                  awarded, before any work starts.
                </span>
              </span>
            </label>
            <label className="grid gap-1">
              <span className="text-sm text-zinc-500">Proposal document</span>
              <input
                type="file"
                onChange={(e) => setBidFile(e.target.files?.[0] ?? null)}
                className="bg-white border border-zinc-300 rounded px-3 py-2 text-sm"
              />
              <span className="text-xs text-zinc-500">
                Its content hash is committed on-chain with your bid. {bidFile && `Uploaded: ${bidFile.name}`}
              </span>
            </label>
            <button
              disabled={busy || bidMilestones.reduce((s, x) => s + (Number(x) || 0), 0) !== Number(bidCost) || !bidCost}
              onClick={submitBid}
              className="bg-sky-500 text-white font-medium rounded-lg px-4 py-2 hover:bg-sky-500 disabled:opacity-40 disabled:cursor-not-allowed"
            >
              {busy
                ? "Submitting…"
                : bidMilestones.reduce((s, x) => s + (Number(x) || 0), 0) !== Number(bidCost)
                  ? "Milestones must sum to your price"
                  : "Submit bid"}
            </button>
          </div>
        )}

        {project.proposals.length === 0 ? (
          <p className="text-zinc-500 text-sm">No bids yet.</p>
        ) : (
          <>
            {["DELIBERATION", "AWARDED", "COMPLETE", "CANCELLED"].includes(project.lifecycle) &&
              project.shortlist.length > 0 && (
                <div className="border border-zinc-200 rounded-lg px-4 py-3 mb-3 flex flex-wrap items-center gap-2">
                  <span className="text-xs text-zinc-500 uppercase tracking-widest mr-1">
                    Shortlist
                  </span>
                  {project.shortlist.map((id) => {
                    const p = project.proposals.find((x) => x.id === id);
                    return (
                      <span
                        key={id}
                        className="px-2.5 py-1 rounded-full text-xs font-medium bg-violet-500/15 text-violet-600 border border-violet-700"
                      >
                        {p?.companyName ?? `Bid #${id}`}
                      </span>
                    );
                  })}
                  <span className="text-xs text-zinc-500 ml-1">
                    — fixed on-chain at close of voting (top {project.numberOfShortlistedProjects} by votes,
                    ties all pass)
                  </span>
                </div>
              )}
            {project.lifecycle === "PROPOSAL" && role !== "committee" && (
              <div className="flex items-start gap-3 border border-zinc-200 bg-zinc-50 rounded-lg px-4 py-3 mb-3">
                <span className="mt-0.5 text-zinc-500">🔒</span>
                <p className="text-zinc-500 text-sm">
                  Bids are sealed while bidding is open so no one can copy or change theirs.
                  They&apos;ll be revealed when voting opens.
                </p>
              </div>
            )}
            <div className="grid gap-3">
              {[...project.proposals]
                .sort((a, b) =>
                  ["DELIBERATION", "AWARDED", "COMPLETE", "CANCELLED"].includes(project.lifecycle)
                    ? Number(b.votes) - Number(a.votes)
                    : 0,
                )
                .map((p, rankIndex) => {
                const sealed =
                  project.lifecycle === "PROPOSAL" &&
                  role !== "committee" &&
                  !(role === "company" && myProposal?.id === p.id);
                const ranked =
                  ["DELIBERATION", "AWARDED", "COMPLETE", "CANCELLED"].includes(project.lifecycle) &&
                  rankIndex < project.proposals.length;
                return (
                  <div key={p.id} className="border border-zinc-200 rounded-lg">
                    {sealed ? (
                      <div className="p-4 flex items-center justify-between gap-4 select-none">
                        <div className="flex-1 grid gap-2">
                          <div className="h-4 w-40 bg-zinc-100 rounded blur-[6px]">Bid #?</div>
                          <div className="h-3 w-64 bg-zinc-100 rounded blur-[6px]">Sealed bid</div>
                        </div>
                        <div className="text-right">
                          <div className="text-lg font-bold text-zinc-500">•</div>
                          <div className="text-xs text-zinc-500">sealed</div>
                        </div>
                      </div>
                    ) : (
                      <>
                        <button
                          onClick={() => toggleBid(p.id)}
                          className="w-full text-left p-4 flex items-center justify-between gap-4 hover:bg-zinc-100 transition rounded-lg"
                        >
                          <div className="flex items-center gap-2">
                            {ranked && (
                              <span
                                className={`w-6 h-6 rounded-full text-xs font-bold flex items-center justify-center shrink-0 ${
                                  rankIndex === 0
                                    ? "bg-amber-500 text-white"
                                    : rankIndex === 1
                                      ? "bg-zinc-900 text-white"
                                      : rankIndex === 2
                                        ? "bg-orange-700 text-white"
                                        : "bg-zinc-100 text-zinc-500"
                                }`}
                              >
                                {rankIndex + 1}
                              </span>
                            )}
                            <div>
                              <div className="font-medium flex items-center gap-2">
                                {p.companyName ?? `Bid #${p.id}`}
                                {["AWARDED", "COMPLETE", "CANCELLED"].includes(project.lifecycle) &&
                                  project.winningProposalId === p.id && (
                                    <span className="px-2 py-0.5 rounded-full text-xs bg-emerald-600 text-white">WINNER</span>
                                  )}
                              </div>
                              <div className="text-sm text-zinc-500">
                                {ges(p.cost)} · milestones: {p.milestones.length ? p.milestones.join(" + ") : "n/a"}
                                {p.depositRequired ? " · deposit" : ""}
                              </div>
                              <div className="text-xs text-zinc-500">by {shortAddr(p.admin)}</div>
                            </div>
                          </div>
                          <div className="flex items-center gap-3">
                            {["DELIBERATION", "AWARDED", "COMPLETE", "CANCELLED"].includes(project.lifecycle) ? (
                              <div className="text-right">
                                <div className="text-lg font-bold text-amber-600">{p.votes}</div>
                                <div className="text-xs text-zinc-500">votes</div>
                              </div>
                            ) : null}
                            {role === "member" && project.lifecycle === "VOTING" &&
                              (meVoted ? (
                                <span
                                  className="px-3 py-1 text-xs rounded-md bg-zinc-100 text-zinc-500 blur-[1px] select-none"
                                  title="You have already voted"
                                >
                                  Voted
                                </span>
                              ) : (
                                <button
                                  disabled={busy}
                                  onClick={(e) => {
                                    e.stopPropagation();
                                    requestVote(p.id);
                                  }}
                                  className="bg-amber-500 text-white font-medium rounded-md px-3 py-1 text-xs hover:bg-amber-500 disabled:opacity-50"
                                >
                                  Vote
                                </button>
                              ))}
                            <span className={`text-zinc-500 transition-transform ${expandedBid === p.id ? "rotate-90" : ""}`}>›</span>
                          </div>
                        </button>

                        {expandedBid === p.id && (
                          <div className="border-t border-zinc-200 px-4 py-4 grid gap-4 text-sm">
                            <div className="grid grid-cols-2 gap-4">
                              <div>
                                <div className="text-xs uppercase tracking-widest text-zinc-500 mb-2">Milestone schedule</div>
                                <div className="grid gap-1">
                                  {p.milestones.map((m, i) => (
                                    <div key={i} className="flex items-center justify-between border border-zinc-200 rounded px-3 py-1.5">
                                      <span className="text-zinc-500">M{i + 1}</span>
                                      <span className="text-zinc-800 font-medium">{ges(m)}</span>
                                    </div>
                                  ))}
                                  <div className="flex items-center justify-between px-3 py-1.5">
                                    <span className="text-zinc-500">Total</span>
                                    <span className="text-emerald-600 font-medium">{ges(p.cost)}</span>
                                  </div>
                                </div>
                              </div>
                              <div className="grid gap-3 content-start">
                                <div>
                                  <div className="text-xs uppercase tracking-widest text-zinc-500 mb-1">Deposit</div>
                                  {p.depositRequired ? (
                                    <p className="text-zinc-700">
                                      Required — M1 ({ges(p.milestones[0] ?? 0)}) is the deposit, released first.
                                    </p>
                                  ) : (
                                    <p className="text-zinc-500">No deposit required.</p>
                                  )}
                                </div>
                                <div>
                                  <div className="text-xs uppercase tracking-widest text-zinc-500 mb-1">Company</div>
                                  <p className="text-zinc-700">{p.companyName ?? "—"}</p>
                                  <p className="text-xs text-zinc-500">by {shortAddr(p.admin)}</p>
                                </div>
                                <div>
                                  <div className="text-xs uppercase tracking-widest text-zinc-500 mb-1">Proposal document</div>
                                  {proposalDocs[p.id]?.length ? (
                                    proposalDocs[p.id].map((d) => (
                                      <a
                                        key={d.id}
                                        href={`/api/documents/${d.id}`}
                                        target="_blank"
                                        className="text-emerald-600 hover:text-emerald-700 underline block"
                                      >
                                        📄 {d.fileName}
                                      </a>
                                    ))
                                  ) : (
                                    <p className="text-zinc-500">No document uploaded — the bid is committed by hash only.</p>
                                  )}
                                </div>
                              </div>
                            </div>
                            <p className="text-xs text-zinc-500 break-all">
                              Spec hash <code>{p.specContentHash}</code>
                            </p>
                          </div>
                        )}
                      </>
                    )}
                  </div>
                );
              })}
            </div>
          </>
        )}
      </div>
      )}

      {/* Committee membership */}
      {(!project.escrow || tab === "info") && project.lifecycle !== "CREATED" && (
        <div className="border border-zinc-200 rounded-xl p-5">
          <div className="flex items-center justify-between mb-3">
            <h2 className="font-semibold">Committee</h2>
            {role === "member" && project.lifecycle !== "AWARDED" &&
              (meOptedIn ? (
                <button
                  disabled
                  className="bg-emerald-600 text-white font-medium rounded-lg px-4 py-2 opacity-60 cursor-default"
                >
                  Opted in
                </button>
              ) : (
                <button
                  disabled={busy}
                  onClick={optin}
                  className="bg-sky-500 text-white font-medium rounded-lg px-4 py-2 hover:bg-sky-500 disabled:opacity-50"
                >
                  Opt into the committee pool
                </button>
              ))}
          </div>
          <p className="text-sm text-zinc-500">
            Members are drawn from the opt-in pool ({project.optedInCount} opted in) using
            on-chain randomness — no one can predict or influence who gets chosen. The committee
            admin is {shortAddr(project.safeWallet)}.
          </p>
          <p className="text-xs text-zinc-500 mt-2">
            Committee members earn a reward of {ges(project.committeeFeePerSignature)} for each
            milestone they review and sign off on — their pay for keeping an eye on the work and
            approving each payment, collected whenever they choose.
          </p>
          {(() => {
            // Members can live in the governance array (VRF draw) or only in
            // the escrow (small pool, everyone serves) - read whichever has them.
            const members = project.committeeMembers.length > 0
              ? project.committeeMembers
              : (project.escrow?.memberSigners ?? []);
            const alternates = project.alternates.length > 0
              ? project.alternates
              : (project.escrow?.alternates ?? []);
            if (members.length === 0 && alternates.length === 0) return null;
            return (
              <div className="mt-3 grid gap-1 text-sm">
                {members.map((m, i) => (
                  <div key={m} className="flex items-center gap-2">
                    <span className="w-2 h-2 rounded-full bg-emerald-400" />
                    {memberNames[m.toLowerCase()] ? (
                      <span className="text-emerald-700 font-medium">{memberNames[m.toLowerCase()]}</span>
                    ) : (
                      <code className="text-emerald-700">{shortAddr(m)}</code>
                    )}
                    <span className="text-zinc-500">member {i + 1}</span>
                  </div>
                ))}
                {alternates.map((m, i) => (
                  <div key={m} className="flex items-center gap-2 opacity-60">
                    <span className="w-2 h-2 rounded-full bg-zinc-400" />
                    <code className="text-zinc-500">{shortAddr(m)}</code>
                    <span className="text-zinc-500">alternate {i + 1}</span>
                  </div>
                ))}
              </div>
            );
          })()}
        </div>
      )}

      {/* Escrow */}
      {project.escrow && tab === "progress" && (
        <div className="border border-zinc-200 rounded-xl p-5">
          <div className="flex items-center justify-between mb-3">
            <h2 className="font-semibold">Escrow — milestone-gated multisig</h2>
            <a className="text-xs underline text-zinc-500 hover:text-emerald-600" href={`https://sepolia.arbiscan.io/address/${project.escrow.address}`} target="_blank">
              {shortAddr(project.escrow.address)} on Arbiscan
            </a>
          </div>

          <div className="grid grid-cols-4 gap-3 mb-4 text-center">
            <div className="bg-white rounded-lg p-3">
              <div className="text-lg font-bold">{ges(project.escrow.balance)}</div>
              <div className="text-xs text-zinc-500">in escrow</div>
            </div>
            <div className="bg-white rounded-lg p-3">
              <div className="text-lg font-bold">{ges(project.escrow.totalReleased)}</div>
              <div className="text-xs text-zinc-500">released</div>
            </div>
            <div className="bg-white rounded-lg p-3">
              <div className="text-lg font-bold">{project.escrow.currentMilestoneIndex}/{project.escrow.milestones.length}</div>
              <div className="text-xs text-zinc-500">milestone</div>
            </div>
            <div className="bg-white rounded-lg p-3">
              <div className="text-lg font-bold">{ges(project.escrow.totalUncollectedFees)}</div>
              <div className="text-xs text-zinc-500">fees owed</div>
            </div>
          </div>

          {project.escrow.milestones.map((m, i) => {
            const isCurrent = i === currentMilestoneIndex && !m.released;
            return (
              <div
                key={i}
                className={`border rounded-lg p-3 mb-2 flex items-center justify-between ${
                  m.released ? "border-emerald-200 bg-emerald-50" : isCurrent ? "border-amber-700 bg-amber-50" : "border-zinc-200"
                }`}
              >
                <div>
                  <div className="font-medium">
                    Milestone {i + 1} · {ges(m.amount)}
                    {m.released && <span className="ml-2 text-emerald-600 text-xs">RELEASED ✓</span>}
                    {isCurrent && <span className="ml-2 text-amber-600 text-xs">CURRENT</span>}
                    {!m.released && sigCounts[i] !== undefined && (
                      <span
                        className={`ml-2 text-xs font-medium ${
                          sigCounts[i] >= releaseRequired ? "text-emerald-600" : "text-zinc-500"
                        }`}
                      >
                        {sigCounts[i]}/{releaseRequired} signatures
                      </span>
                    )}
                  </div>
                  <div className="text-xs text-zinc-500">
                    evidence:{" "}
                    {m.evidenceHash === "0x0000000000000000000000000000000000000000000000000000000000000000"
                      ? "not submitted"
                      : `${m.evidenceHash.slice(0, 18)}…`}
                  </div>
                </div>
                {isCurrent && (
                  <div className="flex items-center gap-2">
                    {role === "company" && project.escrow && wallet === project.escrow.builderSigner.toLowerCase() && (
                      <div className="flex flex-col items-end gap-1.5">
                        {!evidenceSubmitted ? (
                          <label className="grid gap-1 justify-items-end">
                            <span className="text-xs text-zinc-500">Photo of completed work (optional)</span>
                            <input
                              type="file"
                              accept="image/*"
                              className="text-xs"
                              onChange={(e) => setEvidenceFile(e.target.files?.[0] ?? null)}
                            />
                          </label>
                        ) : null}
                        <button
                          disabled={busy || evidenceSubmitted}
                          onClick={submitEvidence}
                          className="bg-sky-500 text-white font-medium rounded-lg px-4 py-2 hover:bg-sky-500 disabled:opacity-50"
                        >
                          {evidenceSubmitted
                            ? "✓ Evidence submitted — awaiting committee approval"
                            : "Submit completion evidence"}
                        </button>
                        {!evidenceSubmitted && (
                          <span className="text-xs text-zinc-500">
                            Declare this milestone complete so the committee can review and approve it
                          </span>
                        )}
                      </div>
                    )}
                    {isSigner && !(role === "company") && (
                      meSigned[i] ? (
                        <span className="bg-emerald-500/15 text-emerald-600 border border-emerald-700 font-medium rounded-lg px-3 py-1.5 text-sm">
                          ✓ Signed
                        </span>
                      ) : (
                        <button
                          disabled={busy || !evidenceSubmitted}
                          onClick={() => approveMilestone(i)}
                          className="bg-emerald-600 text-white font-medium rounded-lg px-3 py-1.5 hover:bg-emerald-500 disabled:opacity-50"
                          title={evidenceSubmitted ? "Sign this milestone" : "Builder must submit evidence first"}
                        >
                          Sign approval
                        </button>
                      )
                    )}
                  </div>
                )}
              </div>
            );
          })}

          <p className="text-xs text-zinc-500 mt-2">
            Release rule: admin <b>AND</b> builder <b>AND</b> ≥1 member (≥3 total) — the release fires
            inside the signature transaction. Signers: admin {shortAddr(project.safeWallet)} · builder{" "}
            {shortAddr(project.escrow.builderSigner)} · members {project.escrow.memberSigners.map(shortAddr).join(", ") || "none (2-of-2 fallback)"}.
          </p>

          {isSigner && !project.escrow.cancelled && (
            <div className="mt-4 border border-zinc-300 rounded-lg p-4 grid gap-2">
              <h3 className="text-sm font-semibold text-red-600">Cancel project</h3>
              <input
                value={reason}
                onChange={(e) => setReason(e.target.value)}
                placeholder="Public on-chain cancellation reason (locked after the first signature)"
                className="bg-white border border-zinc-300 rounded px-3 py-2 text-sm"
              />
              <button
                disabled={busy || !reason}
                onClick={signCancellation}
                className="bg-red-600 text-white font-medium rounded-lg px-4 py-2 hover:bg-red-600 disabled:opacity-50 w-fit"
              >
                Sign cancellation
              </button>
            </div>
          )}

          {role === "member" && Number(project.escrow.totalUncollectedFees) > 0 && (
            <button
              disabled={busy}
              onClick={collectFees}
              className="mt-4 bg-emerald-600 text-white font-medium rounded-lg px-4 py-2 hover:bg-emerald-500 disabled:opacity-50"
            >
              Collect my committee fees
            </button>
          )}
        </div>
      )}

      <p className="text-xs text-zinc-700 text-center">
        This page reads live state from Arbitrum Sepolia every 8 seconds. All actions are real on-chain transactions.
      </p>
    </div>
  );
}