# DemocraFund
### Transparent, on-chain tendering, voting, and escrow for public (and community) projects

**Author:** Gareth Larkan
**Status:** Concept / Pre-build specification
**Pilot partner:** Humewood Golf Club
**Chain:** Arbitrum

---

## 1. Vision & Problem

In South Africa (and many other places), public tenders are routinely awarded through nepotism rather than merit. Money allocated to a project a school, a clinic, a road, is siphoned off before the work is done, with citizens having no visibility into who got the tender, why, or where the money actually went.

**DemocraFund's thesis:** if the entire lifecycle of a tender; the bid, the vote, the award, the fund release is on a public, immutable ledger, corruption gets structurally harder, not just morally discouraged. 

The full vision is national-scale: government departments post tenders, citizens vote on proposals within their area/department of interest, a shortlist goes to government for final award, and funds move through a milestone-gated multisig escrow instead of a lump sum. Evereything on-chain, securing trust, transparency and immutability. 

**This spec covers the MVP**: a working pilot with Humewood Golf Club, where club members play the role of "citizens," the club committee plays "government," club improvement projects (bar upgrade, kitchen renovation, entrance upgrade) play "public projects" and membership fees pay the role of "taxes". The architecture is designed so the leap from "golf club" to "municipality" is a config change, not a rebuild.

---

## 2. Roles & Personas

| Role | National-scale analogue | Humewood MVP analogue |
|---|---|---|
| **Admin / Government** | Government department | Humewood committee |
| **Citizen / Member** | Taxpayer | Paying club member |
| **Builder / Contractor** | Construction company | Contractor/supplier bidding on club work |
| **Milestone Committee** | 1 official + citizens from the area | 1 committee member + 3 randomly-selected members from the relevant department |

Members select one or more **departments** they're interested in (e.g. *Course*, *Clubhouse*, *Energy*, *Machinery*) and vote on tenders in those departments they are eligible for.

---

## 3. End-to-End Lifecycle

1. **Tender creation** — Admin posts a tender (e.g. "Upgrade the entrance area") with a brief, budget ceiling, department tag, and supporting docs uploaded to IPFS. Tender is now publicly visible on-chain (hash + metadata) and in the app.
2. **Proposal submission** — Builders submit proposals: price, timeline, plan/docs (IPFS), broken into **milestones/stages** with a payment % per stage.
3. **Citizen voting** — Members who opted into that department can view all proposals and vote for one. Note: All members may view all tenders and proposals but only opted in members may vote. One member, one vote. Voting window has a defined close time.
4. **Shortlist** — Top 5 (or fewer, if fewer proposals) proposals by vote count are surfaced to Admin.
5. **Government award** — Admin selects the winner from the shortlist (not necessarily #1 — this preserves legitimate government discretion while making an off-list, unvoted choice conspicuous and auditable).
6. **Escrow creation** — On award, an escrow contract is deployed/instantiated for this specific project, funded with the agreed budget in **HumewoodCoin**.
7. **Committee formation** — 1 admin representative + 3 members randomly selected from the department's opted-in pool are assigned as the milestone-approval committee, alongside the builder. This is the 5-signer multisig.
8. **Milestone execution loop** (repeats per stage):
   - Builder marks a stage complete + uploads evidence (photos, invoices) to IPFS.
   - Each of the 5 signers independently inspects/confirms and signs.
   - At **3-of-5 signatures**, the escrow contract auto-releases that stage's payment to the builder's wallet. Note: Builder and admin must sign + any 1 of the 3 randomly selected members. All three members may not band together to just approve.
9. **Project completion** — Final stage released, project marked complete, full history (tender → proposals → votes → award → every milestone signature → every fund movement) remains permanently viewable.

---

## 4. Money Flow: The "Shadow Rand" Model

Real fiat rails (bank integration, card processing, regulated custody) are out of scope for a the MVP. But the *point* of the demo is proving the fund-release logic is real and trustless — so we don't fake the token movement, we fake the edges.

```
[Member pays real ZAR to club when paying membership at the beginning of the year or on monthly debit order] -- (admin bridge, manual for MVP)--> [Wallet credited with HumewoodCoin]
                                                                              |
                                                                              v
                                                        [Project Escrow Contract, funded in HumewoodCoin]
                                                                              |
                                                          3-of-5 multisig approves each stage
                                                                              |
                                                                              v
                                                        [Builder's wallet receives HumewoodCoin]
                                                                              |
                                        (admin bridge, manual for MVP) --> [Builder paid real ZAR]
```

- **HumewoodCoin**: an ERC-20-style token on Arbitrum, designed to look and behave like a stablecoin. Admin-controlled `mint`/`burn`, pausable, 1:1 conceptual peg to ZAR. This is intentionally built as if it *were* a real stablecoin integration, so swapping the manual admin bridge for a real payment processor (Stripe/EFT in, bank payout out) or a regulated custodian later is a plug-in change, not a rewrite.
- **What's real vs. simulated**: The ZAR↔token conversion at the edges is currently a trusted, manual admin action. Everything from the moment tokens enter escrow to the moment they leave is fully on-chain, auditable, and enforced by the multisig, genuinely trustless, not a mockup.
- **Why this matters for the demo**: judges/Humewood can watch a real block explorer and see real fund movement triggered by real multisig signatures. That's the credibility-building moment.

---

## 5. Governance Mechanics

- **Voting**: one member, one vote, per tender, within their opted-in department(s). All votes recorded on chain for visibility.
- **Milestone multisig**: 5 signers (1 admin + 3 randomly-selected department members + 1 builder), **3-of-5 threshold** to release funds.
  - Ensures no single party (including the admin) can unilaterally block or force a release.
  - Builder alone can never self-approve, needs at least 2 more signatures.
  - Committee selection is **random** from the eligible, opted-in member pool per project, to prevent self-nomination or "who you know" gaming, the same failure mode the whole project exists to remove.
- **Government override**: Committee picks the final tender winner from the top-5 shortlist, not necessarily the top vote-getter. This is intentional, preserves legitimate discretion (e.g. compliance checks a pure vote can't capture) while making an unpopular/off-list choice fully visible and explainable, rather than hidden.

---

## 6. System Architecture (High-Level)

**On-chain (Arbitrum, Sepolia testnet for MVP):**
- `TenderRegistry.sol` — create/list tenders, store IPFS doc hashes, department tag, status.
- `ProposalRegistry.sol` — builder proposals linked to a tender, milestone breakdown, IPFS docs.
- `VotingContract.sol` — records votes per tender per eligible member (see §7 on gas trade-offs).
- `HumewoodCoin.sol` — ERC-20, admin mint/burn/pause.
- `ProjectEscrow.sol` — deployed per awarded tender (factory pattern via `EscrowFactory.sol`); holds funds, defines milestone stages, enforces 3-of-5 multisig release logic, plus a separate higher-threshold breach/termination action (see §7.1).
- `CommitteeSelector.sol` — integrates Chainlink VRF to randomly draw the 3 citizen signers (and replacements) from the eligible, opted-in member pool for a project's department.

**Off-chain:**
- **Backend (Node/Express or similar)**: custodial wallet management (key generation/encryption per member on signup), auth (email/password), orchestrates IPFS uploads, syncs on-chain events to a readable feed for the frontend, handles the manual ZAR↔token admin bridge actions, and runs the gas sponsorship layer (see §6.1).
- **Database (Postgres)**: member profiles, department preferences, session/auth data, cached on-chain state for fast UI reads (never the source of truth for money — chain is always canonical).
- **IPFS (via Pinata or web3.storage)**: all tender docs, proposal docs, milestone evidence photos, and reject-vote justification evidence (see §7).
- **Frontend (React)**: member-facing app that *feels* like a normal web app — no wallet popups, no gas-fee prompts, no seed phrases. Wallet is fully abstracted behind login (per your decision).

### 6.1 Gas Sponsorship (users never touch gas or sign anything)

Because members are fully custodial, the backend already holds their private key, so it can sign **and submit** every transaction on their behalf. A member clicking "Vote" or "Approve stage" never sees a wallet, a signature prompt, or a gas fee.

The only real requirement: whichever address is submitting a transaction needs native ETH to pay for it. MVP approach:

- Backend maintains a funded **treasury wallet**.
- Before submitting a transaction for a member, backend checks their custodial wallet's ETH balance; if insufficient, it auto-tops-up a small amount from the treasury first. Entirely invisible to the user.

This is intentionally the simple version. Two more sophisticated patterns exist and are worth naming in the pitch as roadmap items rather than building now:

- **Meta-transactions (EIP-2771 / Gas Station Network)** — the standard fix *when users self-custody*: they sign a message off-chain, a relayer submits and pays gas on their behalf. Not needed yet since custody already solves the signing problem, but relevant the moment DemocraFund offers a self-custody option.
- **ERC-4337 Account Abstraction + Paymaster** — the production-grade answer for a public, national-scale deployment: every user gets a smart-contract wallet, gas can be sponsored or paid in any token, and the system stops depending on Humewood's backend being the sole custodian of every key (a meaningful centralization/security concern at scale — worth flagging explicitly to a security-minded audience as the deliberate next evolution, not an oversight).

Each member still gets a distinct, real on-chain address even though the backend holds the key — so every vote and every milestone signature remains cryptographically attributable to a specific person. The audit trail isn't sacrificed by removing friction, only the friction is.

---

## 7. Dispute Resolution (documented for the pitch, not built for MVP)

Not implemented in the MVP, but the design is specified now so it can be pointed to honestly as "solved on paper, next to build" rather than an unnoticed gap.

- **Stalled signer.** A citizen or official signer doesn't respond within a defined window (e.g. 7 days).
  - Citizen signer: auto-replaced via a fresh Chainlink VRF draw from the eligible, opted-in member pool — reuses the same randomness mechanism as initial committee formation, so it's a natural extension rather than new logic.
  - Admin/official signer: there's only one, so a timeout can't just redraw. Likely needs a designated deputy-admin role who can stand in after a timeout. Flagged as an open design question — not fully resolved.
- **Contested milestone.** A signer disagrees that a stage is complete. Any **reject** vote requires a written reason plus supporting evidence (photos, docs) uploaded to IPFS, visible to everyone alongside approve votes. This gives a bad-faith rejection the same public accountability cost as a bad-faith approval — nobody can silently veto without justifying it in public.
- **Builder abandonment / breach.** A separate, deliberately higher-threshold action — **4-of-5, drawn from the same 5 committee members** (1 admin + 3 citizens + builder, though the builder obviously can't approve their own termination in practice) — can redirect remaining escrow funds (e.g. back to the club treasury, or to a replacement builder). Requires mandatory public on-chain justification, same evidence pattern as a milestone rejection. Making this threshold harder to reach than a normal release is intentional: terminating a builder is a heavier action and shouldn't be triggerable by the same bare majority that approves routine progress.
- **Process appeals.** Currently no path exists if someone believes a signer replacement or a rejection was itself unfair, beyond raising it with the admin directly. This is a genuine open gap — a mature version likely needs a broader member-jury appeal mechanism. Worth stating plainly in the pitch rather than glossing over.

---

## 8. Roadmap Beyond MVP

- Real fiat on/off-ramp (regulated stablecoin custodian or licensed payment processor).
- ERC-4337 account abstraction + Paymaster, removing reliance on backend custody as the sole key holder.
- Move from single-club pilot to multi-department municipal deployment.
- KYC/identity verification for citizen eligibility at scale.
- Build out the dispute resolution logic specified in §7 (currently designed, not implemented).
- Deputy-admin / official-signer-timeout mechanism.
- Member-jury appeal process.
- Possible move to a dedicated Arbitrum Subnet for the national-scale version (custom gas token, validator control, compliance hooks).
