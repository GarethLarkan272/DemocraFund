# DemocraFund — The Endgame

### From Humewood Golf Club to national-scale public tendering

**Status:** Vision & roadmap. The implemented MVP is documented in [README.md](./README.md) — this document is what comes next, what it takes to get there, and the open design questions we are deliberately not papering over.

---

## 1. Where the MVP ends and the Endgame begins

The MVP proves one thing with real, inspectable code: **a tender lifecycle can run trustlessly on-chain** — bids, votes, a vote-bound shortlist, an award, and milestone-gated multisig payouts where no single person can move money. Humewood Golf Club is the pilot: members vote, the committee administers, and real fund movement happens against real multisig signatures on a public block explorer.

The leap to national scale is *not* a rewrite. Every component in the MVP was built with its national-scale analogue in mind:

| MVP (Humewood pilot) | National-scale (Endgame) |
|---|---|
| Club members vote | Citizens vote within their department/ward |
| Club committee administers | Government departments post tenders |
| Membership fees as the shadow "taxes" | Real tax-funded budgets |
| GES "shadow rand", manual admin off-ramp | Regulated stablecoin / licensed payment processor |
| Backend-custodial wallets | Self-custody via ERC-4337 smart wallets |
| One club, one community | Many municipalities, many departments |

---

## 2. The product thesis at scale

The same structural argument that makes a golf club pilot compelling becomes overwhelming for a municipality:

1. **Corruption is a coordination problem, not a morals problem.** Nepotistic awards survive because the paper trail is private. Put every decision — who bid, who voted, who was awarded, who signed off each payment, where each cent went — on an immutable public ledger, and the cost of each corrupt act includes the permanent, verifiable record of it.
2. **The vote is the check on the award.** Government keeps discretion (a shortlist, not a dictat), but the contracts make an *unvoted* choice impossible. The MVP already enforces this on-chain; scale just adds identity so "one citizen one vote" is real.
3. **The escrow is the check on the spending.** Milestone-gated multisig payouts mean budget is released against signed, evidenced work — not a lump sum with a prayer. Every rand of public money flows through rules anyone can audit.
4. **The receipt is the check on the money.** Every token has a terminal artifact: minted → escrowed → released per milestone → burned at off-ramp → fiat paid, with a transferable receipt NFT as the permanent link. That receipt becomes the **builder track record** — a public, verified history of completed public work that travels with the builder.

---

## 3. Roadmap (what's to come, in rough order)

### 3.1 Short-term (pilot hardening)

- **Production deploy tooling.** Fill in the VRF `subscriptionId`, automated consumer registration, multi-sig governance for the platform roles, and a deployment verification flow (contract verification, admin UI, block-explorer dashboard for the demo).
- **A frontend.** Members need a simple app: view tenders, vote, opt in, approve stages ("Approve stage" with evidence preview), see the escrow balance and every payment.
- **Off-ramp polish.** The manual admin burn-bridge becomes a documented operations runbook with reconciliation (every receipt NFT ↔ every fiat payout), then a licensed payment processor integration.
- **Deputy-admin mechanism.** A single official signer is the MVP's weakest operational point; a designated deputy (with role-based fallback) is the first governance upgrade.

### 3.2 Medium-term (real users, real money)

- **ERC-4337 account abstraction + Paymaster.** Smart-contract wallets for every user; gas sponsored or paid in GES; the backend is no longer the sole custodian of every key. This is the step that makes the system *custody-optional*: members can self-custody while the club keeps the frictionless custodial option.
- **KYC/identity + department-scoped voting.** Citizen eligibility and department membership become on-chain (or zk-attested) claims, so "one citizen, one vote, in the right ward" is enforced, not assumed.
- **Reject votes for contested milestones.** Any signer can reject a milestone with a written, evidenced justification (IPFS) — bad-faith rejection costs the same public accountability as bad-faith approval.
- **Member-jury appeals.** A signed-off dispute path for contested promotions, rejections, and cancellations — the missing fourth leg of the dispute resolution story.
- **Committee redraw via fresh VRF.** Alternates cover the MVP; at scale, a stalled committee can also be re-drawn from the pool entirely.

### 3.3 Long-term (national scale)

- **Multi-department, multi-municipality deployment.** One factory, many departments; a platform admin provisions departments with their own voting pools, budgets, and reporting surfaces.
- **A regulated stablecoin or licensed processor.** Swap the GES shadow-rand for a real 1:1-backed instrument — the MVP's token contract was deliberately built to make this a config change.
- **Builder track records as a first-class primitive.** Receipt NFTs accrue per builder: verified public-works history, dispute record, on-time performance — a portable reputation that rewards competence across tenders.
- **Arbitrum Subnet.** A dedicated L2 with custom gas token, validator control, and compliance hooks for government data-handling requirements.

---

## 4. Open design questions (honestly flagged)

These are deliberately **not** swept under the rug. Each is a genuine decision point for the next phase:

1. **Who is the platform admin, really?** The deployer holds platform-wide roles today. At scale, that must become a multisig (likely a committee of departments + an auditor) — the MVP is a single-tenant pilot, the endgame is shared infrastructure.
2. **Settlement semantics.** `releaseSettlement` lets the admin compensate the builder before a cancellation finalises. Scope and policy (who can propose, what evidence, caps) need product rules beyond the smart-contract cap.
3. **One company, one wallet.** The MVP's registry is deliberately strict. At scale, companies may need multiple admin wallets, multiple payment wallets, and a review/approval step for registration — without breaking the "bids never carry wallets" property.
4. **Vote-weighting.** Flat one-address-one-vote is the MVP. Departments with large populations, residents vs. members, and anti-sybil requirements will force a weighting decision (likely zk-attested residency).
5. **Committee compensation at scale.** Fee accrual is capped per signature and pull-based. At scale, compensation policy (tax treatment, caps, whether fees should even exist for civil servants) is a governance question, not a code question.
6. **Stalled official signer.** There is only one admin signer and no good answer yet. Options: deputy admin, time-based delegation, or a quorum shift. Needs a deliberate design pass before real deployments depend on it.
7. **Frontend trust.** The MVP assumes a backend relayer. A hostile frontend can lie about what it shows members. The escape hatch is that every claim is verifiable on-chain (signatures, digests, balances) — but "verify yourself" tooling (block explorer deep links, signed app binaries, open-source UI) is a roadmap deliverable in its own right.

---

## 5. What "done" looks like

The Endgame is reached when **a citizen can**, without trusting anyone at the front door:

1. See every tender in their department, every bid, and every vote on a public ledger.
2. Vote — knowing their vote is a real, attributable on-chain record.
3. Watch an award happen only from the vote-bound shortlist.
4. Watch every payment leave an escrow only against signed, evidenced milestone work.
5. Follow every token to its terminal receipt: minted, escrowed, released, burned, paid out in fiat — with a paper trail from the municipal budget line to a builder's bank account.
6. See a builder's entire public-works track record, earned proof-by-proof, without a single word from the builder's own marketing team.

The MVP already implements 1–5 at the pilot scale. The Endgame is the same architecture, with identity, custody, rails, and scale — and a jurisdiction willing to let public money flow through it.
