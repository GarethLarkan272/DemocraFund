"use client";

import { useEffect, useState } from "react";
import Link from "next/link";

type Company = {
  name: string;
  onChainId: number;
  adminWallet: string;
  infoHash: string;
  active: boolean;
};

function shortAddr(a: string) {
  return a ? `${a.slice(0, 6)}…${a.slice(-4)}` : "—";
}

export default function Company() {
  const [company, setCompany] = useState<Company | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    fetch("/api/company/register")
      .then((r) => r.json())
      .then((d) => setCompany(d.company))
      .catch(() => setCompany(null))
      .finally(() => setLoading(false));
  }, []);

  return (
    <div className="max-w-lg mx-auto">
      <Link href="/" className="text-sm text-zinc-500 hover:text-emerald-600 inline-block mb-4">
        ← Back to tender board
      </Link>
      <h1 className="text-2xl font-bold mb-2">Company / Builder</h1>

      {loading ? (
        <p className="text-zinc-500 text-sm">Loading…</p>
      ) : !company ? (
        <div className="border border-zinc-200 rounded-xl p-5 text-sm">
          <p className="text-zinc-700">
            You haven&apos;t registered a company yet. Sign up as a company and the registration form
            will collect your payment wallet and company information.
          </p>
          <Link
            href="/signup"
            className="inline-block mt-4 bg-emerald-600 text-white font-medium rounded-lg px-4 py-2 hover:bg-emerald-500"
          >
            Sign up as a company
          </Link>
        </div>
      ) : (
        <div className="grid gap-3 text-sm">
          <p className="text-zinc-500">
            Registered on-chain as company{" "}
            <span className="font-mono text-emerald-700">#{company.onChainId}</span> —{" "}
            <span className="text-zinc-800 font-medium">{company.name}</span>
          </p>
          <div className="border border-zinc-200 rounded-xl p-4 grid gap-2">
            <p>
              <span className="text-zinc-500">Wallet </span>
              <code className="text-emerald-700">{shortAddr(company.adminWallet)}</code>
              <span className="text-zinc-500 text-xs ml-2">identity — payouts land here</span>
            </p>
            <p className="break-all">
              <span className="text-zinc-500">Info hash </span>
              <code className="text-zinc-500 text-xs">{company.infoHash}</code>
            </p>
          </div>
          <p className="text-zinc-500 text-sm">
            Now head to an open tender on the board and submit your bid.
          </p>
          <Link
            href="/"
            className="bg-emerald-600 text-white font-medium rounded-lg px-4 py-2 text-center hover:bg-emerald-500"
          >
            Go to tender board
          </Link>
        </div>
      )}
    </div>
  );
}