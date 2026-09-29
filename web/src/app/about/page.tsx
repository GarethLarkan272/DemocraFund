"use client";

import { useState } from "react";

const FAQS = [
  {
    q: "How does the money work?",
    a: "The club's budget is held in a secure digital escrow for each project. The winning company is paid in stages as work is completed — never in one lump sum upfront. Each payment needs the builder, a club administrator, and a community member to all approve it. Nothing is paid to a company's bank account until the work for that stage is signed off.",
  },
  {
    q: "How do I tender as a company?",
    a: "Register a company account on the Sign up page — you'll need to add your company details and a document such as your registration or tax certificate. Once registered, you can bid on any open tender by submitting your price and a breakdown of milestone amounts, plus a description of what you'll deliver. A deposit can be requested on some projects, which is released first when you win.",
  },
  {
    q: "How do I vote?",
    a: "When a tender's bidding closes, voting opens for a set period. Members vote for the proposals they think should win — you can see every bid, the price, and the milestone breakdown. Once voting closes, the top-voted proposals are shortlisted and the committee picks the winner from that shortlist.",
  },
  {
    q: "What is a committee for a project?",
    a: "When a project is awarded, a small committee is drawn randomly from the members who opted in — no one can influence who is chosen. This committee reviews the work at each milestone and must approve each payment before the company is paid. They earn a small fee for each milestone they sign off. If a committee member is unavailable, an alternate takes their place.",
  },
  {
    q: "Who can see what's happening?",
    a: "Everything is visible to club members: the tender details, every company's bid, the votes, who was drawn to the committee, and every payment as it's released. The record is stored on a public blockchain, so nothing can be silently changed or deleted afterwards.",
  },
  {
    q: "What if I want my tokens paid out to my bank?",
    a: "Once your company has earned tokens (from milestone payments) or you've earned committee fees, you can redeem them in your account page. The tokens are burned and a receipt is issued, which the club's paying authority honours with a real bank payout.",
  },
];

export default function About() {
  const [openFaq, setOpenFaq] = useState<number | null>(0);

  return (
    <div className="max-w-3xl mx-auto grid gap-12 pb-16">
      <section className="text-center pt-6">
        <h1 className="text-3xl font-bold tracking-tight">How the system works</h1>
        <p className="text-zinc-600 mt-3 leading-relaxed">
          Club projects — clubhouse upgrades, course improvements, and more — are opened to fair
          tendering. Companies bid, members vote, and payments only happen as work is completed and
          approved. Everything is recorded transparently, so every member can see where the money goes.
        </p>
      </section>

      <section>
        <h2 className="text-xl font-bold text-center mb-6">How it works</h2>
        <div className="grid sm:grid-cols-2 gap-4">
          {[
            {
              step: "1",
              title: "Tender is posted",
              body: "The club posts the work, the budget, and the deadlines — committed on-chain for everyone to see.",
            },
            {
              step: "2",
              title: "Companies bid openly",
              body: "Any registered company can bid with a full milestone schedule and price. Bids are sealed until the deadline.",
            },
            {
              step: "3",
              title: "Members vote",
              body: "A committee is drawn by verifiable randomness — no one can predict or influence who gets chosen.",
            },
            {
              step: "4",
              title: "Milestone-gated payments",
              body: "The winner is paid as the work completes, each release requiring multiple signatures — nobody moves funds alone.",
            },
          ].map((c) => (
            <div key={c.step} className="border border-zinc-200 rounded-xl p-5 bg-white">
              <div className="w-8 h-8 rounded-full bg-emerald-600 text-white flex items-center justify-center text-sm font-bold mb-3">
                {c.step}
              </div>
              <div className="font-semibold mb-1">{c.title}</div>
              <div className="text-sm text-zinc-600 leading-relaxed">{c.body}</div>
            </div>
          ))}
        </div>
      </section>

      <section>
        <h2 className="text-xl font-bold text-center mb-6">Frequently asked questions</h2>
        <div className="grid gap-3">
          {FAQS.map((f, i) => (
            <div key={f.q} className="border border-zinc-200 rounded-xl bg-white overflow-hidden">
              <button
                type="button"
                onClick={() => setOpenFaq(openFaq === i ? null : i)}
                className="w-full text-left px-5 py-4 flex items-center justify-between gap-4 hover:bg-zinc-50 transition"
              >
                <span className="font-semibold">{f.q}</span>
                <span className={`text-zinc-500 text-lg transition-transform ${openFaq === i ? "rotate-45" : ""}`}>
                  +
                </span>
              </button>
              {openFaq === i && (
                <div className="px-5 pb-5 text-sm text-zinc-600 leading-relaxed">{f.a}</div>
              )}
            </div>
          ))}
        </div>
      </section>
    </div>
  );
}