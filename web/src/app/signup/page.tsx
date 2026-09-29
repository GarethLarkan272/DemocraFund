"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import ErrorBanner from "@/components/error-banner";

const ROLES = [
  { id: "member", label: "Member / Citizen", desc: "Vote on tenders, opt into committees, approve work" },
  { id: "company", label: "Company / Builder", desc: "Register, bid on tenders, get paid per milestone" },
  { id: "committee", label: "Committee / Admin", desc: "The club committee - creates tenders, runs the lifecycle" },
  { id: "payer", label: "Paying authority", desc: "Marks off-ramp redemptions as paid" },
];

function PasswordInput({
  value,
  onChange,
  placeholder,
  visible,
  onToggle,
}: {
  value: string;
  onChange: (v: string) => void;
  placeholder: string;
  visible: boolean;
  onToggle: () => void;
}) {
  return (
    <div className="relative">
      <input
        className="bg-white border border-zinc-300 rounded-lg px-4 py-2.5 pr-24 w-full"
        placeholder={placeholder}
        type={visible ? "text" : "password"}
        value={value}
        onChange={(e) => onChange(e.target.value)}
      />
      <button
        type="button"
        onClick={onToggle}
        className="absolute right-2 top-1/2 -translate-y-1/2 text-xs text-zinc-500 hover:text-emerald-600 px-2 py-1"
      >
        {visible ? "Hide" : "Show"}
      </button>
    </div>
  );
}

export default function Signup() {
  const router = useRouter();
  const [username, setUsername] = useState("");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [confirm, setConfirm] = useState("");
  const [passwordVisible, setPasswordVisible] = useState(false);
  const [role, setRole] = useState("member");
  const [companyName, setCompanyName] = useState("");
  const [infoFile, setInfoFile] = useState<File | null>(null);
  const [error, setError] = useState("");
  const [busy, setBusy] = useState(false);

  const isCompany = role === "company";

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    if (password !== confirm) return setError("Passwords don't match");
    setBusy(true);
    setError("");
    const form = new FormData();
    form.set("username", username);
    form.set("email", email);
    form.set("password", password);
    form.set("role", role);
    if (isCompany) {
      form.set("companyName", companyName);
      if (infoFile) form.set("infoFile", infoFile);
    }
    const res = await fetch("/api/auth/signup", { method: "POST", body: form });
    const data = await res.json();
    setBusy(false);
    if (!res.ok) return setError(data.error);
    router.push("/");
    router.refresh();
  }

  return (
    <div className="max-w-md mx-auto mt-10">
      <h1 className="text-2xl font-bold mb-2">Create an account</h1>
      <p className="text-zinc-500 text-sm mb-6">
        No wallet needed - DemocraFund derives your on-chain identity for you. Your votes and
        signatures are still real, attributable on-chain records.
      </p>
      <form onSubmit={submit} className="grid gap-4">
        <div className="grid gap-2">
          <span className="text-sm text-zinc-500">What are you?</span>
          {ROLES.map((r) => (
            <label
              key={r.id}
              className={`flex items-start gap-3 border rounded-lg px-4 py-3 cursor-pointer ${
                role === r.id ? "border-emerald-500 bg-emerald-500/5" : "border-zinc-200 hover:border-zinc-300"
              }`}
            >
              <input
                type="radio"
                name="role"
                className="mt-1 accent-emerald-500"
                checked={role === r.id}
                onChange={() => setRole(r.id)}
              />
              <span>
                <span className="font-medium block">{r.label}</span>
                <span className="text-xs text-zinc-500">{r.desc}</span>
              </span>
            </label>
          ))}
        </div>

        <input
          className="bg-white border border-zinc-300 rounded-lg px-4 py-2.5"
          placeholder="Username"
          value={username}
          onChange={(e) => setUsername(e.target.value)}
        />
        <input
          className="bg-white border border-zinc-300 rounded-lg px-4 py-2.5"
          placeholder="Email (optional)"
          type="email"
          value={email}
          onChange={(e) => setEmail(e.target.value)}
        />
        <PasswordInput
          placeholder="Password (6+ chars)"
          value={password}
          onChange={setPassword}
          visible={passwordVisible}
          onToggle={() => setPasswordVisible(!passwordVisible)}
        />
        <PasswordInput
          placeholder="Confirm password"
          value={confirm}
          onChange={setConfirm}
          visible={passwordVisible}
          onToggle={() => setPasswordVisible(!passwordVisible)}
        />

        {isCompany && (
          <div className="border border-zinc-200 rounded-xl p-4 grid gap-3">
            <span className="text-sm text-zinc-500">
              Company registration <span className="text-xs text-zinc-500">(registered on-chain)</span>
            </span>
            <input
              className="bg-white border border-zinc-300 rounded-lg px-4 py-2.5"
              placeholder="Company name"
              value={companyName}
              onChange={(e) => setCompanyName(e.target.value)}
              required={isCompany}
            />
            <label className="grid gap-1">
              <span className="text-sm text-zinc-500">
                Company information <span className="text-xs text-zinc-500">(docs, registration, tax IDs)</span>
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
                Its content hash is committed on-chain as your company&apos;s info hash.
              </span>
            </label>
          </div>
        )}

        {error && <ErrorBanner error={error} onDismiss={() => setError("")} />}
        <button
          disabled={busy}
          className="bg-emerald-600 text-white font-medium rounded-lg py-2.5 hover:bg-emerald-500 disabled:opacity-50"
        >
          {busy ? "Creating…" : "Create account"}
        </button>
      </form>
    </div>
  );
}