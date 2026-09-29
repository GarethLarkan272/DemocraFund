"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import ErrorBanner from "@/components/error-banner";

export default function Login() {
  const router = useRouter();
  const [username, setUsername] = useState("");
  const [password, setPassword] = useState("");
  const [visible, setVisible] = useState(false);
  const [error, setError] = useState("");
  const [busy, setBusy] = useState(false);

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError("");
    const res = await fetch("/api/auth/login", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ username, password }),
    });
    const data = await res.json();
    setBusy(false);
    if (!res.ok) return setError(data.error);
    router.push("/");
    router.refresh();
  }

  return (
    <div className="max-w-sm mx-auto mt-16">
      <h1 className="text-2xl font-bold mb-6">Login</h1>
      <form onSubmit={submit} className="grid gap-4">
        <input
          className="bg-white border border-zinc-300 rounded-lg px-4 py-2.5"
          placeholder="Username"
          value={username}
          onChange={(e) => setUsername(e.target.value)}
        />
        <div className="relative">
          <input
            className="bg-white border border-zinc-300 rounded-lg px-4 py-2.5 pr-24 w-full"
            placeholder="Password"
            type={visible ? "text" : "password"}
            value={password}
            onChange={(e) => setPassword(e.target.value)}
          />
          <button
            type="button"
            onClick={() => setVisible(!visible)}
            className="absolute right-2 top-1/2 -translate-y-1/2 text-xs text-zinc-500 hover:text-emerald-600 px-2 py-1"
          >
            {visible ? "Hide" : "Show"}
          </button>
        </div>
        {error && <ErrorBanner error={error} onDismiss={() => setError("")} />}
        <button
          disabled={busy}
          className="bg-emerald-600 text-white font-medium rounded-lg py-2.5 hover:bg-emerald-500 disabled:opacity-50"
        >
          {busy ? "Logging in…" : "Login"}
        </button>
      </form>
    </div>
  );
}