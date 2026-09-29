"use client";

import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import { useEffect, useState } from "react";

type Me = { user: { username: string; role: string } | null; wallet?: string };

export function Header() {
  const [me, setMe] = useState<Me | null>(null);
  const pathname = usePathname();
  const router = useRouter();

  useEffect(() => {
    fetch("/api/auth/me")
      .then((r) => r.json())
      .then(setMe)
      .catch(() => setMe(null));
  }, [pathname]);

  return (
    <header className="border-b border-zinc-200 bg-white sticky top-0 z-20">
      <div className="max-w-6xl mx-auto px-4 h-16 flex items-center justify-between">
        <div className="flex items-center gap-8">
          <Link href="/tenders" className="leading-none">
            <span className="block font-bold tracking-tight text-lg text-zinc-900">
              Democra<span className="text-emerald-600">Fund</span>
            </span>
            <span className="block text-[9px] text-zinc-500 mt-0.5">Humewood Golf Club</span>
          </Link>
          <nav className="flex items-center gap-5 text-sm">
            <Link
              href="/tenders"
              className={`hover:text-emerald-600 ${
                pathname === "/tenders" ? "text-emerald-600 font-medium" : "text-zinc-700"
              }`}
            >
              Tenders
            </Link>
            <Link
              href="/about"
              className={`hover:text-emerald-600 ${
                pathname === "/about" ? "text-emerald-600 font-medium" : "text-zinc-700"
              }`}
            >
              About
            </Link>
            {me?.user?.role === "payer" && (
              <Link href="/payer" className="hover:text-emerald-600 text-zinc-700">
                Payments
              </Link>
            )}
          </nav>
        </div>
        <div className="flex items-center gap-5 text-sm">
          {me?.user ? (
            <>
              <Link href="/account" className="flex items-center gap-2 hover:text-emerald-600 text-zinc-700">
                <span className="w-2 h-2 rounded-full bg-emerald-500" />
                {me.user.username}
              </Link>
              <button
                onClick={async () => {
                  await fetch("/api/auth/me", { method: "POST" });
                  setMe(null);
                  router.push("/tenders");
                  router.refresh();
                }}
                className="text-zinc-500 hover:text-red-600"
              >
                Log out
              </button>
            </>
          ) : (
            <>
              <Link href="/login" className="hover:text-emerald-600 text-zinc-700">
                Login
              </Link>
              <Link
                href="/signup"
                className="px-3 py-1.5 rounded-md bg-emerald-600 text-white font-medium hover:bg-emerald-500"
              >
                Sign up
              </Link>
            </>
          )}
        </div>
      </div>
    </header>
  );
}