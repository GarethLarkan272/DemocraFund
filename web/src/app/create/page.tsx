"use client";

import { useEffect, useMemo, useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import ErrorBanner from "@/components/error-banner";

const MIN_MS = 60 * 1000;

function fmt(date: Date) {
  return date.toLocaleString([], {
    weekday: "short",
    month: "short",
    day: "numeric",
    hour: "2-digit",
    minute: "2-digit",
  });
}

function Section({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <section className="border border-zinc-200 rounded-xl p-5 grid gap-4">
      <h2 className="text-xs uppercase tracking-widest text-zinc-500 font-semibold">{title}</h2>
      {children}
    </section>
  );
}

function Field({ label, hint, children }: { label: string; hint?: string; children: React.ReactNode }) {
  return (
    <label className="grid gap-1.5">
      <span className="text-sm text-zinc-700">
        {label}
        {hint && <span className="text-zinc-500 text-xs ml-2">{hint}</span>}
      </span>
      {children}
    </label>
  );
}

const inputClass = "bg-white border border-zinc-300 rounded-lg px-4 py-2.5 focus:border-emerald-600 focus:outline-none";

// The chosen date+time as a datetime-local input value.
function toLocalInput(ts: number) {
  const d = new Date(ts);
  const pad = (n: number) => String(n).padStart(2, "0");
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`;
}

export default function CreateTender() {
  const router = useRouter();
  const [authorized, setAuthorized] = useState<null | boolean>(null);
  const [title, setTitle] = useState("");
  const [description, setDescription] = useState("");
  const [department, setDepartment] = useState("Clubhouse");
  const [category, setCategory] = useState("Improvement");
  const [budgetCap, setBudgetCap] = useState("5000");
  const [fee, setFee] = useState("10");
  const [proposalDate, setProposalDate] = useState(() => toLocalInput(Date.now() + 10 * MIN_MS));
  const [votingDate, setVotingDate] = useState(() => toLocalInput(Date.now() + 20 * MIN_MS));
  const [awardDate, setAwardDate] = useState(() => toLocalInput(Date.now() + 30 * MIN_MS));
  const [file, setFile] = useState<File | null>(null);
  const [images, setImages] = useState<File[]>([]);
  const [error, setError] = useState("");
  const [busy, setBusy] = useState(false);

  const [now] = useState(() => Date.now());

  useEffect(() => {
    fetch("/api/auth/me")
      .then((r) => r.json())
      .then((m) => setAuthorized(m.user?.role === "committee"))
      .catch(() => setAuthorized(false));
  }, []);

  const schedule = useMemo(() => {
    const p = new Date(proposalDate).getTime();
    const v = new Date(votingDate).getTime();
    const a = new Date(awardDate).getTime();
    return {
      proposal: new Date(p),
      voting: new Date(v),
      award: new Date(a),
      valid: p > now && v > p && a > v,
    };
  }, [proposalDate, votingDate, awardDate, now]);

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError("");
    const form = new FormData();
    form.set("title", title);
    form.set("description", description);
    form.set("department", department);
    form.set("category", category);
    form.set("budgetCap", budgetCap);
    form.set("committeeFeePerSignature", fee);
    form.set("proposalDeadline", String(new Date(proposalDate).getTime() / 1000));
    form.set("votingDeadline", String(new Date(votingDate).getTime() / 1000));
    form.set("awardDeadline", String(new Date(awardDate).getTime() / 1000));
    if (file) form.set("specFile", file);
    images.forEach((img, i) => form.set(`image_${i}`, img));

    const res = await fetch("/api/project/create", { method: "POST", body: form });
    const data = await res.json();
    setBusy(false);
    if (!res.ok) return setError(data.error ?? "Failed to create tender");
    router.push(`/projects/${data.governance}`);
  }

  if (authorized === null) return <p className="text-zinc-500">Loading…</p>;

  if (authorized === false) {
    return (
      <div className="max-w-xl mx-auto">
        <div className="flex items-start gap-3 border border-amber-200 bg-amber-50 rounded-xl px-4 py-3">
          <span className="mt-0.5 text-amber-600">⚠</span>
          <div>
            <p className="text-amber-600 text-sm font-medium">Committee only</p>
            <p className="text-amber-200/70 text-sm mt-1">
              Only the committee admin account can create tenders. Members can view tenders, vote, and opt in.
            </p>
          </div>
        </div>
      </div>
    );
  }

  return (
    <div className="max-w-2xl mx-auto">
      <Link href="/" className="text-sm text-zinc-500 hover:text-emerald-600 inline-block mb-4">
        ← Back to tender board
      </Link>
      <div className="mb-8">
        <h1 className="text-3xl font-bold tracking-tight">Create a tender</h1>
        <p className="text-zinc-500 mt-1">
          Timeline in hours — minimum 1 hour per stage. Deadlines are locked on-chain at creation.
        </p>
      </div>

      <form onSubmit={submit} className="grid gap-6">
        <Section title="Tender details">
          <Field label="Title">
            <input
              className={inputClass}
              value={title}
              onChange={(e) => setTitle(e.target.value)}
              required
              placeholder="e.g. Upgrade the clubhouse entrance"
            />
          </Field>
          <Field label="Description" hint="what the work involves, why it's needed">
            <textarea
              className={`${inputClass} min-h-28 resize-y`}
              value={description}
              onChange={(e) => setDescription(e.target.value)}
              placeholder="e.g. Replace the entrance doors, repaint the foyer, and install a wheelchair ramp…"
            />
          </Field>
          <div className="grid grid-cols-2 gap-4">
            <Field label="Department">
              <input
                className={inputClass}
                value={department}
                onChange={(e) => setDepartment(e.target.value)}
              />
            </Field>
            <Field label="Category">
              <input
                className={inputClass}
                value={category}
                onChange={(e) => setCategory(e.target.value)}
              />
            </Field>
          </div>
        </Section>

        <Section title="Budget">
          <div className="grid grid-cols-2 gap-4">
            <Field label="Budget cap" hint="Rands">
              <input
                className={inputClass}
                value={budgetCap}
                onChange={(e) => setBudgetCap(e.target.value)}
                type="number"
                min="1"
                required
              />
            </Field>
            <Field label="Committee fee per signature" hint="Rands">
              <input
                className={inputClass}
                value={fee}
                onChange={(e) => setFee(e.target.value)}
                type="number"
                min="0"
              />
            </Field>
          </div>
          <p className="text-xs text-zinc-500">
            The escrow is funded with the budget plus a fee reserve for every committee signature, paid out to
            members as milestones release.
          </p>
        </Section>

        <Section title="Timeline">
          <p className="text-sm text-zinc-500">
            Pick the date and time each stage closes. The award deadline is the last moment the
            committee may choose a winner after voting.
          </p>
          <div className="grid grid-cols-3 gap-3 items-end">
            <Field label="Bidding closes" hint="companies stop submitting bids">
              <input
                className={`${inputClass} !px-2.5 !py-1.5 text-sm`}
                value={proposalDate}
                onChange={(e) => setProposalDate(e.target.value)}
                type="datetime-local"
                step="600"
                required
              />
            </Field>
            <Field label="Voting closes" hint="members stop voting">
              <input
                className={`${inputClass} !px-2.5 !py-1.5 text-sm`}
                value={votingDate}
                onChange={(e) => setVotingDate(e.target.value)}
                type="datetime-local"
                step="600"
                required
              />
            </Field>
            <Field label="Award by" hint="committee picks the winner">
              <input
                className={`${inputClass} !px-2.5 !py-1.5 text-sm`}
                value={awardDate}
                onChange={(e) => setAwardDate(e.target.value)}
                type="datetime-local"
                step="600"
                required
              />
            </Field>
          </div>
          <div className="rounded-lg bg-white/60 border border-zinc-200 px-4 py-3 text-sm text-zinc-500 grid gap-1">
            <p>
              Bids close <span className="text-zinc-900 font-medium">{fmt(schedule.proposal)}</span>
            </p>
            <p>
              Voting closes <span className="text-zinc-900 font-medium">{fmt(schedule.voting)}</span>
            </p>
            <p>
              Award no later than <span className="text-zinc-900 font-medium">{fmt(schedule.award)}</span>
            </p>
            {!schedule.valid && (
              <p className="text-red-600 text-sm mt-1">
                Dates must be in the future and in order: bidding closes first, then voting, then the
                award deadline.
              </p>
            )}
          </div>
        </Section>

        <Section title="Specification">
          <Field label="Tender specification document" hint="optional">
            <input
              type="file"
              className={`${inputClass} text-sm`}
              onChange={(e) => setFile(e.target.files?.[0] ?? null)}
            />
          </Field>
          <Field label="Photos / site images" hint="optional, multiple">
            <input
              type="file"
              accept="image/*"
              multiple
              className={`${inputClass} text-sm`}
              onChange={(e) => setImages(Array.from(e.target.files ?? []))}
            />
            {images.length > 0 && (
              <span className="text-xs text-zinc-500">{images.length} image(s) selected</span>
            )}
          </Field>
        </Section>

        {error && <ErrorBanner error={error} onDismiss={() => setError("")} />}
        <button
          disabled={busy}
          className="bg-emerald-600 text-white font-medium rounded-lg py-3 hover:bg-emerald-500 disabled:opacity-50"
        >
          {busy ? "Creating on-chain…" : "Create tender"}
        </button>
      </form>
    </div>
  );
}