"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import ErrorBanner from "@/components/error-banner";

type Me = { user: { username: string; role: string } | null; wallet?: string };

type Receipt = { tokenId: string; amount: string; state: string; payoutRef: string };

type Company = {
  id: number;
  name: string;
  onChainId: number;
  adminWallet: string;
  infoHash: string;
  active: boolean;
};

function shortAddr(a: string) {
  return a ? `${a.slice(0, 6)}…${a.slice(-4)}` : "—";
}

const RECEIPT_COLORS: Record<string, string> = {
  Pending: "bg-amber-500 text-white",
  Paid: "bg-emerald-600 text-white",
  Rejected: "bg-red-600 text-white",
};

type TenderMoney = {
  governance: string;
  title: string;
  lifecycle: string;
  totalProjectBudget: string;
  feeReserve: string;
  totalReleased: string;
  settlementPaid: string;
  feesCollected: string;
  totalUncollectedFees: string;
  totalReturnedOnCancellation: string;
  totalSweptToTreasury: string;
  balance: string;
  milestonesReleased: number;
  milestonesTotal: number;
};

type MoneyData = {
  tenders: TenderMoney[];
  totals: {
    tenders: number;
    funded: number;
    released: number;
    feesCollected: number;
    feesOwed: number;
    settlementPaid: number;
    returned: number;
    swept: number;
    balance: number;
  };
  leaderboard: { wallet: string; credits: string }[];
};

type CompanyRow = {
  name: string;
  onChainId: number;
  adminWallet: string;
  active: boolean;
  bids: number;
  wins: number;
};

type CompaniesData = {
  companies: CompanyRow[];
  totals: { registered: number; active: number; bidding: number };
};

type CompanyActivity = {
  bids: {
    governance: string;
    tenderTitle: string;
    proposalId: number;
    cost: string;
    milestones: string[];
    depositRequired: boolean;
    lifecycle: string;
    won: boolean;
  }[];
  totals: { submitted: number; won: number; inProgress: number };
};

type OverviewData = {
  tenders: { total: number; byLifecycle: Record<string, number> };
  money: { funded: string; released: string; owed: string };
  companies: { registered: number };
  pendingRedemptions: number;
  pendingActions: { governance: string; title: string; action: string; label: string }[];
};

const fmtR = (n: number | string) =>
  `R${(Number(n)).toLocaleString(undefined, { maximumFractionDigits: 2 })}`;

const LIFECYCLE_BADGE: Record<string, string> = {
  CREATED: "bg-zinc-300",
  PROPOSAL: "bg-sky-500",
  VOTING: "bg-amber-500",
  DELIBERATION: "bg-violet-500",
  AWARDED: "bg-emerald-500",
  COMPLETE: "bg-emerald-700",
  CANCELLED: "bg-red-600",
};

export default function Account() {
  const router = useRouter();
  const [me, setMe] = useState<Me | null>(null);
  const [company, setCompany] = useState<Company | null>(null);
  const [infoFile, setInfoFile] = useState<File | null>(null);
  const [balance, setBalance] = useState<string | null>(null);
  const [receipts, setReceipts] = useState<Receipt[]>([]);
  const [redeemAmount, setRedeemAmount] = useState("");
  const [provenance, setProvenance] = useState<{ governance: string; escrow: string; title: string }[]>([]);
  const [redeemEscrow, setRedeemEscrow] = useState("");
  const [error, setError] = useState("");
  const [busy, setBusy] = useState(false);
  const [tab, setTab] = useState<"overview" | "account" | "money" | "companies" | "info" | "bids">(
    "overview",
  );
  const [money, setMoney] = useState<MoneyData | null>(null);
  const [companiesData, setCompaniesData] = useState<CompaniesData | null>(null);
  const [overview, setOverview] = useState<OverviewData | null>(null);
  const [activity, setActivity] = useState<CompanyActivity | null>(null);
  const [fees, setFees] = useState<{ tenders: { governance: string; title: string; owed: string }[]; totalOwed: string } | null>(null);
  const [collecting, setCollecting] = useState<string | null>(null);

  useEffect(() => {
    Promise.all([
      fetch("/api/auth/me").then((r) => r.json()),
      fetch("/api/company/register").then((r) => r.json()),
      fetch("/api/redeem").then((r) => r.json()),
      fetch("/api/company/activity").then((r) => r.json()),
      fetch("/api/fees").then((r) => r.json()),
    ])
      .then(([m, c, rm, act, feesData]) => {
        setMe(m);
        setCompany(c.company ?? null);
        setBalance(rm.balance ?? "0");
        setReceipts(rm.receipts ?? []);
        setActivity(act.bids ? act : null);
        setFees(feesData.tenders ? feesData : null);
        setProvenance(rm.provenance ?? []);
        setRedeemEscrow(rm.provenance?.[0]?.escrow ?? "");
        if (m?.user?.role === "company") setTab("info");
        else if (m?.user?.role === "committee") setTab("overview");
        else setTab("account");
      })
      .catch(() => setMe(null));
  }, []);

  async function redeem(e: React.FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError("");
    const res = await fetch("/api/redeem", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ amount: redeemAmount, escrow: redeemEscrow || undefined }),
    });
    const data = await res.json();
    setBusy(false);
    if (!res.ok) return setError(data.error ?? "Redemption failed");
    setRedeemAmount("");
    const rm = await fetch("/api/redeem").then((r) => r.json());
    setBalance(rm.balance ?? "0");
    setReceipts(rm.receipts ?? []);
    setProvenance(rm.provenance ?? []);
    setRedeemEscrow(rm.provenance?.[0]?.escrow ?? "");
  }

  async function collectFees(governance: string) {
    setCollecting(governance);
    setError("");
    try {
      const res = await fetch("/api/fees", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ governance }),
      });
      const data = await res.json();
      if (!res.ok) return setError(data.error ?? "Collection failed");
      const feesData = await fetch("/api/fees").then((r) => r.json());
      setFees(feesData.tenders ? feesData : null);
    } catch (e) {
      setError(String(e));
    } finally {
      setCollecting(null);
    }
  }

  if (!me) return <p className="text-zinc-500">Loading…</p>;
  if (!me.user) {
    router.push("/login");
    return null;
  }

  async function logout() {
    await fetch("/api/auth/me", { method: "POST" });
    router.push("/");
    router.refresh();
  }

  async function saveCompany(e: React.FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError("");
    const form = new FormData();
    if (infoFile) form.set("infoFile", infoFile);
    const res = await fetch("/api/company/update", { method: "PATCH", body: form });
    const data = await res.json();
    setBusy(false);
    if (!res.ok) return setError(data.error ?? "Update failed");
    setCompany((c) => (c ? { ...c, infoHash: data.infoHash, active: data.active } : c));
    setInfoFile(null);
  }

  async function toggleActive() {
    setBusy(true);
    setError("");
    const form = new FormData();
    form.set("active", String(!company?.active));
    const res = await fetch("/api/company/update", { method: "PATCH", body: form });
    const data = await res.json();
    setBusy(false);
    if (!res.ok) return setError(data.error ?? "Update failed");
    setCompany((c) => (c ? { ...c, active: data.active } : c));
  }

  const isCompany = me.user.role === "company";
  const isCommittee = me.user.role === "committee";

  async function openOverview() {
    setTab("overview");
    if (!overview) {
      const res = await fetch("/api/admin/overview");
      const data = await res.json();
      if (data.tenders) setOverview(data);
    }
  }

  async function openMoney() {
    setTab("money");
    if (!money) {
      const res = await fetch("/api/admin/money");
      const data = await res.json();
      if (data.tenders) setMoney(data);
    }
  }

  async function openCompanies() {
    setTab("companies");
    if (!companiesData) {
      const res = await fetch("/api/admin/companies");
      const data = await res.json();
      if (data.companies) setCompaniesData(data);
    }
  }

  return (
    <div className="max-w-4xl">
      <Link href="/" className="text-sm text-zinc-500 hover:text-emerald-600 inline-block mb-4">
        ← Back to tender board
      </Link>
      <h1 className="text-2xl font-bold mb-6">Your account</h1>

      {isCommittee && (
        <div className="flex gap-2 mb-6 border-b border-zinc-200">
          <button type="button"
    onClick={openOverview}
            className={`px-4 py-2 text-sm font-medium border-b-2 -mb-px transition ${
              tab === "overview"
                ? "border-emerald-500 text-emerald-600"
                : "border-transparent text-zinc-500 hover:text-zinc-700"
            }`}
          >
            Overview
          </button>
          <button
            onClick={() => setTab("account")}
            className={`px-4 py-2 text-sm font-medium border-b-2 -mb-px transition ${
              tab === "account"
                ? "border-emerald-500 text-emerald-600"
                : "border-transparent text-zinc-500 hover:text-zinc-700"
            }`}
          >
            Account
          </button>
          <button type="button"
    onClick={openMoney}
            className={`px-4 py-2 text-sm font-medium border-b-2 -mb-px transition ${
              tab === "money"
                ? "border-emerald-500 text-emerald-600"
                : "border-transparent text-zinc-500 hover:text-zinc-700"
            }`}
          >
            Money
          </button>
          <button type="button"
    onClick={openCompanies}
            className={`px-4 py-2 text-sm font-medium border-b-2 -mb-px transition ${
              tab === "companies"
                ? "border-emerald-500 text-emerald-600"
                : "border-transparent text-zinc-500 hover:text-zinc-700"
            }`}
          >
            Companies
          </button>
        </div>
      )}

      {isCompany && (
        <div className="flex gap-2 mb-6 border-b border-zinc-200">
          <button
            type="button"
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
            type="button"
            onClick={() => setTab("money")}
            className={`px-4 py-2 text-sm font-medium border-b-2 -mb-px transition ${
              tab === "money"
                ? "border-emerald-500 text-emerald-600"
                : "border-transparent text-zinc-500 hover:text-zinc-700"
            }`}
          >
            Money
          </button>
          <button
            type="button"
            onClick={() => setTab("bids")}
            className={`px-4 py-2 text-sm font-medium border-b-2 -mb-px transition ${
              tab === "bids"
                ? "border-emerald-500 text-emerald-600"
                : "border-transparent text-zinc-500 hover:text-zinc-700"
            }`}
          >
            Bids
          </button>
        </div>
      )}

      {tab === "overview" && isCommittee ? (
        overview ? (
          <div className="grid gap-6">
            <div className="grid grid-cols-4 gap-3">
              <div className="border border-zinc-200 rounded-xl p-4">
                <div className="text-xs text-zinc-500 uppercase tracking-wider">Tenders</div>
                <div className="text-xl font-bold mt-1">{overview.tenders.total}</div>
              </div>
              <div className="border border-zinc-200 rounded-xl p-4">
                <div className="text-xs text-zinc-500 uppercase tracking-wider">Funded</div>
                <div className="text-xl font-bold text-emerald-600 mt-1">{fmtR(overview.money.funded)}</div>
              </div>
              <div className="border border-zinc-200 rounded-xl p-4">
                <div className="text-xs text-zinc-500 uppercase tracking-wider">Fees owed</div>
                <div className="text-xl font-bold text-amber-600 mt-1">{fmtR(overview.money.owed)}</div>
              </div>
              <div className="border border-zinc-200 rounded-xl p-4">
                <div className="text-xs text-zinc-500 uppercase tracking-wider">Companies</div>
                <div className="text-xl font-bold mt-1">{overview.companies.registered}</div>
              </div>
            </div>

            {overview.pendingActions.length > 0 && (
              <div className="border border-zinc-200 rounded-xl p-5">
                <h2 className="font-semibold mb-3">Needs your attention</h2>
                <div className="grid gap-2">
                  {overview.pendingActions.map((a) => (
                    <div key={a.governance} className="flex items-center justify-between border border-zinc-200 rounded-lg px-4 py-3">
                      <div>
                        <div className="font-medium text-sm">{a.title}</div>
                        <div className="text-xs text-zinc-500">Tender is waiting — {a.label.toLowerCase()}</div>
                      </div>
                      <Link
                        href={`/projects/${a.governance}`}
                        className="bg-emerald-600 text-white font-medium rounded-md px-3 py-1.5 text-sm hover:bg-emerald-500"
                      >
                        Handle
                      </Link>
                    </div>
                  ))}
                </div>
              </div>
            )}

            <div className="border border-zinc-200 rounded-xl p-5">
              <h2 className="font-semibold mb-3">Tenders by stage</h2>
              {overview.tenders.total === 0 ? (
                <p className="text-zinc-500 text-sm">No tenders yet.</p>
              ) : (
                <div className="flex flex-wrap gap-2">
                  {Object.entries(overview.tenders.byLifecycle).map(([stage, n]) => (
                    <span
                      key={stage}
                      className={`px-3 py-1.5 rounded-full text-xs font-medium ${LIFECYCLE_BADGE[stage] ?? "bg-zinc-300"}`}
                    >
                      {stage} · {n}
                    </span>
                  ))}
                </div>
              )}
            </div>

            {overview.pendingRedemptions > 0 && (
              <div className="border border-amber-200 bg-amber-50 rounded-xl px-4 py-3 flex items-center justify-between">
                <p className="text-amber-600 text-sm">
                  {overview.pendingRedemptions} redemption{overview.pendingRedemptions === 1 ? "" : "s"} awaiting
                  the paying authority.
                </p>
                <Link href="/payer" className="text-amber-600 underline text-sm hover:text-amber-600">
                  Review
                </Link>
              </div>
            )}
          </div>
        ) : (
          <p className="text-zinc-500">Loading overview…</p>
        )
      ) : tab === "companies" && isCommittee ? (
        companiesData ? (
          <div className="grid gap-6">
            <div className="grid grid-cols-3 gap-3">
              <div className="border border-zinc-200 rounded-xl p-4">
                <div className="text-xs text-zinc-500 uppercase tracking-wider">Registered</div>
                <div className="text-xl font-bold mt-1">{companiesData.totals.registered}</div>
              </div>
              <div className="border border-zinc-200 rounded-xl p-4">
                <div className="text-xs text-zinc-500 uppercase tracking-wider">Active</div>
                <div className="text-xl font-bold text-emerald-600 mt-1">{companiesData.totals.active}</div>
              </div>
              <div className="border border-zinc-200 rounded-xl p-4">
                <div className="text-xs text-zinc-500 uppercase tracking-wider">Bidding</div>
                <div className="text-xl font-bold text-sky-600 mt-1">{companiesData.totals.bidding}</div>
              </div>
            </div>

            <div className="border border-zinc-200 rounded-xl p-5">
              <h2 className="font-semibold mb-3">Companies</h2>
              {companiesData.companies.length === 0 ? (
                <p className="text-zinc-500 text-sm">No companies registered yet.</p>
              ) : (
                <div className="grid gap-2">
                  {companiesData.companies.map((c) => (
                    <div key={c.onChainId} className="border border-zinc-200 rounded-lg p-4 flex items-center justify-between">
                      <div>
                        <div className="flex items-center gap-2">
                          <span className="font-medium">{c.name}</span>
                          <span className="text-xs text-zinc-500">#{c.onChainId}</span>
                          <span
                            className={`px-2 py-0.5 rounded-full text-xs font-medium ${
                              c.active ? "bg-emerald-600 text-white" : "bg-zinc-300 text-zinc-700"
                            }`}
                          >
                            {c.active ? "ACTIVE" : "DEACTIVATED"}
                          </span>
                        </div>
                        <div className="text-xs text-zinc-500 mt-1">
                          <code>{shortAddr(c.adminWallet)}</code>
                        </div>
                      </div>
                      <div className="flex gap-6 text-right">
                        <div>
                          <div className="text-lg font-bold text-sky-600">{c.bids}</div>
                          <div className="text-xs text-zinc-500">bids</div>
                        </div>
                        <div>
                          <div className="text-lg font-bold text-emerald-600">{c.wins}</div>
                          <div className="text-xs text-zinc-500">wins</div>
                        </div>
                      </div>
                    </div>
                  ))}
                </div>
              )}
            </div>
          </div>
        ) : (
          <p className="text-zinc-500">Loading companies…</p>
        )
      ) : tab === "money" && isCommittee ? (
        money ? (
          <div className="grid gap-6">
            <div className="grid grid-cols-4 gap-3">
              <div className="border border-zinc-200 rounded-xl p-4">
                <div className="text-xs text-zinc-500 uppercase tracking-wider">Funded</div>
                <div className="text-xl font-bold text-emerald-600 mt-1">{fmtR(money.totals.funded)}</div>
              </div>
              <div className="border border-zinc-200 rounded-xl p-4">
                <div className="text-xs text-zinc-500 uppercase tracking-wider">Released</div>
                <div className="text-xl font-bold mt-1">{fmtR(money.totals.released)}</div>
              </div>
              <div className="border border-zinc-200 rounded-xl p-4">
                <div className="text-xs text-zinc-500 uppercase tracking-wider">Fees owed</div>
                <div className="text-xl font-bold text-amber-600 mt-1">{fmtR(money.totals.feesOwed)}</div>
              </div>
              <div className="border border-zinc-200 rounded-xl p-4">
                <div className="text-xs text-zinc-500 uppercase tracking-wider">In escrow now</div>
                <div className="text-xl font-bold mt-1">{fmtR(money.totals.balance)}</div>
              </div>
            </div>

            <div className="border border-zinc-200 rounded-xl p-5">
              <h2 className="font-semibold mb-3">Tenders</h2>
              <div className="grid gap-2">
                {money.tenders.length === 0 && <p className="text-zinc-500 text-sm">No funded tenders yet.</p>}
                {money.tenders.map((t) => (
                  <div key={t.governance} className="border border-zinc-200 rounded-lg p-4">
                    <div className="flex items-center justify-between">
                      <div className="flex items-center gap-2">
                        <span className={`px-2 py-0.5 rounded-full text-xs font-medium ${LIFECYCLE_BADGE[t.lifecycle] ?? "bg-zinc-300"}`}>
                          {t.lifecycle}
                        </span>
                        <span className="font-medium">{t.title}</span>
                      </div>
                      <span className="text-xs text-zinc-500">
                        {t.milestonesReleased}/{t.milestonesTotal} milestones released
                      </span>
                    </div>
                    <div className="grid grid-cols-3 gap-3 mt-3 text-sm">
                      <div>
                        <div className="text-xs text-zinc-500">Budget</div>
                        <div>{fmtR(t.totalProjectBudget)}</div>
                      </div>
                      <div>
                        <div className="text-xs text-zinc-500">Released</div>
                        <div className="text-emerald-600">{fmtR(t.totalReleased)}</div>
                      </div>
                      <div>
                        <div className="text-xs text-zinc-500">Fee reserve</div>
                        <div>{fmtR(t.feeReserve)}</div>
                      </div>
                      <div>
                        <div className="text-xs text-zinc-500">Fees collected</div>
                        <div>{fmtR(t.feesCollected)}</div>
                      </div>
                      <div>
                        <div className="text-xs text-zinc-500">Fees owed</div>
                        <div className="text-amber-600">{fmtR(t.totalUncollectedFees)}</div>
                      </div>
                      <div>
                        <div className="text-xs text-zinc-500">Swept to treasury</div>
                        <div>{fmtR(t.totalSweptToTreasury)}</div>
                      </div>
                    </div>
                  </div>
                ))}
              </div>
            </div>

            {money.leaderboard.length > 0 && (
              <div className="border border-zinc-200 rounded-xl p-5">
                <h2 className="font-semibold mb-3">Fee hall of fame</h2>
                <div className="grid gap-2">
                  {money.leaderboard.map((m, i) => (
                    <div key={m.wallet} className="flex items-center justify-between border border-zinc-200 rounded-lg px-4 py-2.5">
                      <div className="flex items-center gap-3">
                        <span
                          className={`w-6 h-6 rounded-full text-xs font-bold flex items-center justify-center ${
                            i === 0
                              ? "bg-amber-500 text-white"
                              : i === 1
                                ? "bg-zinc-900 text-white"
                                : i === 2
                                  ? "bg-orange-700 text-white"
                                  : "bg-zinc-100 text-zinc-500"
                          }`}
                        >
                          {i + 1}
                        </span>
                        <code className="text-emerald-700 text-sm">{shortAddr(m.wallet)}</code>
                      </div>
                      <span className="text-sm text-zinc-700">{fmtR(m.credits)} earned</span>
                    </div>
                  ))}
                </div>
              </div>
            )}
          </div>
        ) : (
          <p className="text-zinc-500">Loading money overview…</p>
        )
      ) : (
      <div className="border border-zinc-200 rounded-xl p-6 grid gap-5">
        <div className="flex items-center justify-between">
          <div>
            <div className="font-semibold text-lg">{me.user.username}</div>
            <div className="text-zinc-500 text-sm capitalize">{me.user.role}</div>
          </div>
          <button type="button" onClick={logout} className="text-sm text-zinc-500 hover:text-red-600">
            Logout
          </button>
        </div>

        {/* Balance + redemption (Money tab for companies) */}
        {(isCompany ? tab === "money" : true) && (
        <div className="border-t border-zinc-200 pt-5">
          <div className="flex items-center justify-between">
            <div className="text-xs text-zinc-500 uppercase tracking-wider">Available balance</div>
            <span className="text-2xl font-bold text-emerald-600">{fmtR(balance ?? 0)}</span>
          </div>

          <form onSubmit={redeem} className="grid gap-3 mt-4">
            <div className="text-xs text-zinc-500">
              Redeem your balance: it is burned and you receive a receipt NFT that the paying
              authority honours with a real payout.
            </div>
            {provenance.length > 0 && (
              <label className="grid gap-1">
                <span className="text-xs text-zinc-500">These tokens came from</span>
                <select
                  value={redeemEscrow}
                  onChange={(e) => setRedeemEscrow(e.target.value)}
                  className="bg-white border border-zinc-300 rounded-lg px-3 py-2.5 text-sm"
                >
                  {provenance.map((p) => (
                    <option key={p.escrow} value={p.escrow}>
                      {p.title}
                    </option>
                  ))}
                </select>
              </label>
            )}
            <div className="flex gap-3">
              <input
                value={redeemAmount}
                onChange={(e) => setRedeemAmount(e.target.value)}
                type="number"
                min="1"
                step="1"
                placeholder="Amount in Rands"
                className="bg-white border border-zinc-300 rounded-lg px-4 py-2.5 flex-1"
                required
              />
              <button
                type="submit"
                disabled={busy || !redeemAmount || Number(redeemAmount) > Number(balance ?? 0)}
                className="bg-emerald-600 text-white font-medium rounded-lg px-5 py-2.5 hover:bg-emerald-500 disabled:opacity-40 disabled:cursor-not-allowed"
              >
                {busy ? "Redeeming…" : "Redeem"}
              </button>
            </div>
          </form>

          {receipts.length > 0 && (
            <div className="mt-5">
              <div className="text-xs text-zinc-500 uppercase tracking-wider mb-2">Your redemption receipts</div>
              <div className="grid gap-2">
                {receipts.map((r) => (
                  <div key={r.tokenId} className="border border-zinc-200 rounded-lg p-3 flex items-center justify-between">
                    <div>
                      <div className="font-medium text-sm">Receipt #{r.tokenId}</div>
                      <div className="text-xs text-zinc-500">
                        {fmtR(r.amount)} burned
                        {r.state === "Paid" && ` · ref ${r.payoutRef}`}
                      </div>
                    </div>
                    <span className={`px-2 py-0.5 rounded-full text-xs font-medium ${RECEIPT_COLORS[r.state] ?? "bg-zinc-300"}`}>
                      {r.state}
                    </span>
                  </div>
                ))}
              </div>
            </div>
          )}

          {fees && fees.tenders.length > 0 && (
            <div className="border-t border-zinc-200 pt-5 grid gap-3">
              <div className="flex items-center justify-between">
                <div className="text-xs text-zinc-500 uppercase tracking-wider">Committee fees owed</div>
                <div className="text-sm font-semibold text-amber-600">
                  {fmtR(fees.totalOwed)}
                </div>
              </div>
              <div className="grid gap-2">
                {fees.tenders.map((t) => (
                  <div
                    key={t.governance}
                    className="flex items-center justify-between border border-zinc-200 rounded-lg px-4 py-3"
                  >
                    <div>
                      <Link
                        href={`/projects/${t.governance}`}
                        className="text-sm font-medium hover:text-emerald-600"
                      >
                        {t.title}
                      </Link>
                      <div className="text-xs text-zinc-500">
                        {fmtR(t.owed)} uncollected
                      </div>
                    </div>
                    <button
                      type="button"
                      disabled={busy || collecting !== null}
                      onClick={() => collectFees(t.governance)}
                      className="bg-amber-500 text-white font-medium rounded-lg px-4 py-2 text-sm hover:bg-amber-500 disabled:opacity-40 disabled:cursor-not-allowed"
                    >
                      {collecting === t.governance ? "Collecting…" : "Collect"}
                    </button>
                  </div>
                ))}
              </div>
            </div>
          )}
        </div>
        )}

        {isCompany && tab === "info" && (
          <div className="border-t border-zinc-200 pt-5 grid gap-4">
            <div className="flex items-center justify-between">
              <div className="text-xs text-zinc-500 uppercase tracking-wider">
                Company{" "}
                {company && (
                  <span
                    className={`ml-2 px-2 py-0.5 rounded-full text-xs font-medium ${
                      company.active ? "bg-emerald-600 text-white" : "bg-zinc-300 text-zinc-700"
                    }`}
                  >
                    {company.active ? "ACTIVE" : "DEACTIVATED"}
                  </span>
                )}
              </div>
            </div>

            {!company ? (
              <p className="text-zinc-500 text-sm">
                No company registered on this account. Sign up as a company to register one.
              </p>
            ) : (
              <form onSubmit={saveCompany} className="grid gap-4">
                <div className="grid grid-cols-2 gap-4 text-sm">
                  <div>
                    <div className="text-xs text-zinc-500 uppercase tracking-wider mb-1">Company name</div>
                    <div className="text-zinc-800">{company.name}</div>
                  </div>
                  <div>
                    <div className="text-xs text-zinc-500 uppercase tracking-wider mb-1">Wallet</div>
                    <code className="text-emerald-700 text-xs">{shortAddr(company.adminWallet)}</code>
                    <span className="text-zinc-500 text-xs ml-1">(identity — payouts land here)</span>
                  </div>
                </div>

                <label className="grid gap-1">
                  <span className="text-sm text-zinc-500">
                    Company information{" "}
                    <span className="text-zinc-500 text-xs">(docs, registration, tax IDs)</span>
                  </span>
                  {infoFile ? (
                    <div className="flex items-center justify-between bg-white border border-zinc-300 rounded-lg px-4 py-2.5 text-sm">
                      <span className="text-zinc-700 truncate">{infoFile.name}</span>
                      <button
                        type="button"
                        onClick={() => setInfoFile(null)}
                        className="text-zinc-500 hover:text-red-600 shrink-0 ml-3"
                      >
                        Remove ✕
                      </button>
                    </div>
                  ) : (
                    <input
                      type="file"
                      className="bg-white border border-zinc-300 rounded-lg px-4 py-2.5 text-sm"
                      onChange={(e) => setInfoFile(e.target.files?.[0] ?? null)}
                    />
                  )}
                  <span className="text-xs text-zinc-500">
                    Current info hash: <code className="text-zinc-500">{shortAddr(company.infoHash)}</code>
                  </span>
                </label>

                {error && <ErrorBanner error={error} onDismiss={() => setError("")} />}

                <div className="flex flex-wrap items-center gap-3">
                  <button
                    type="submit"
                    disabled={busy}
                    className="bg-emerald-600 text-white font-medium rounded-lg px-4 py-2 hover:bg-emerald-500 disabled:opacity-50"
                  >
                    {busy ? "Saving on-chain…" : "Save company details"}
                  </button>
                  <button
                    type="button"
                    disabled={busy}
                    onClick={toggleActive}
                    className={`font-medium rounded-lg px-4 py-2 disabled:opacity-50 ${
                      company.active
                        ? "bg-red-600 text-white hover:bg-red-600"
                        : "bg-emerald-600 text-white hover:bg-emerald-500"
                    }`}
                  >
                    {company.active ? "Deactivate company" : "Activate company"}
                  </button>
                </div>
                <p className="text-xs text-zinc-500">
                  {company.active
                    ? "While active, your company can bid on open tenders."
                    : "While inactive, your company cannot bid — existing bids are unaffected."}
                </p>
              </form>
            )}
          </div>
        )}

        {isCompany && tab === "bids" && activity && activity.bids.length > 0 && (
          <div className="border-t border-zinc-200 pt-5">
            <div className="flex items-center justify-between">
              <div className="text-xs text-zinc-500 uppercase tracking-wider">Your bids</div>
              <div className="text-xs text-zinc-500">
                <span className="text-emerald-600 font-medium">{activity.totals.won}</span> won ·{" "}
                <span className="text-sky-600 font-medium">{activity.totals.inProgress}</span> in progress
              </div>
            </div>
            <div className="grid gap-2 mt-3">
              {activity.bids.map((b) => (
                <Link
                  key={`${b.governance}-${b.proposalId}`}
                  href={`/projects/${b.governance}`}
                  className="border border-zinc-200 rounded-lg p-3 flex items-center justify-between hover:border-emerald-600 transition"
                >
                  <div>
                    <div className="flex items-center gap-2">
                      <span className="font-medium text-sm">{b.tenderTitle}</span>
                      {b.won && (
                        <span className="px-2 py-0.5 rounded-full text-xs font-medium bg-emerald-600 text-white">
                          WON
                        </span>
                      )}
                    </div>
                    <div className="text-xs text-zinc-500 mt-0.5">
                      Bid #{b.proposalId} · {fmtR(b.cost)} ·{" "}
                      {b.milestones.length} milestone{b.milestones.length === 1 ? "" : "s"}
                      {b.depositRequired ? " · deposit" : ""}
                    </div>
                  </div>
                  <span
                    className={`px-2 py-0.5 rounded-full text-xs font-medium ${
                      LIFECYCLE_BADGE[b.lifecycle] ?? "bg-zinc-300"
                    }`}
                  >
                    {b.lifecycle}
                  </span>
                </Link>
              ))}
            </div>
          </div>
        )}

        {isCompany && tab === "bids" && (!activity || activity.bids.length === 0) && (
          <div className="border-t border-zinc-200 pt-5">
            <div className="text-xs text-zinc-500 uppercase tracking-wider mb-3">Your bids</div>
            <p className="text-zinc-500 text-sm">
              No bids yet. Browse the tender board and submit a bid on an open tender.
            </p>
          </div>
        )}
        </div>
      )}
    </div>
  );
}