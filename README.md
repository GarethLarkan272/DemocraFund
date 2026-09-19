# DemocraFund
### Transparent, on-chain tendering, voting, and escrow for public (and community) projects

**Author:** Gareth Larkan
**Status:** Implemented MVP — Foundry/Solidity contracts with a full test suite (`src/`, 137 tests: unit + fuzz + invariant + end-to-end flows)
**Pilot partner:** Humewood Golf Club
**Chain:** Arbitrum (testnet deployment: Arbitrum Sepolia)

> **Two documents.** This README is the complete, current specification of the MVP: what the system is, how it works, how the contracts interact, where every unit of money moves, worked examples, and every access-control rule. The future — national-scale vision, roadmap, and open design questions — lives in [ENDGAME.md](./ENDGAME.md).

---

## 1. Vision & Problem

In South Africa (and many other places), public tenders are routinely awarded through nepotism rather than merit. Money allocated to a project — a school, a clinic, a road — is siphoned off before the work is done, with citizens having no visibility into who got the tender, why, or where the money actually went.

**DemocraFund's thesis:** if the entire lifecycle of a tender — the bid, the vote, the award, the fund release — is on a public, immutable ledger, corruption gets structurally harder, not just morally discouraged.

The full vision is national-scale: government departments post tenders, citizens vote on proposals within their area/department of interest, a shortlist goes to government for final award, and funds move through a milestone-gated multisig escrow instead of a lump sum. Everything on-chain, securing trust, transparency and immutability.

**This document covers the MVP**: a working pilot with Humewood Golf Club, where club members play the role of "citizens," the club committee plays "government," club improvement projects (bar upgrade, kitchen renovation, entrance upgrade) play "public projects" and membership fees play the role of "taxes". The architecture is designed so the leap from "golf club" to "municipality" is a config change, not a rebuild.

---

## 2. Roles & Personas

| Role | National-scale analogue | Humewood MVP analogue |
|---|---|---|
| **Admin / Government** | Government department | Humewood committee |
| **Citizen / Member** | Taxpayer | Paying club member |
| **Builder / Contractor** | Construction company | Contractor/supplier bidding on club work |
| **Milestone Committee** | 1 official + citizens from the area | 1 committee admin + up to 3 randomly-selected members from the project's opt-in pool (+ the builder) |
| **Paying authority** | Bank / payment processor | The person honouring off-ramps in real money |

Every tender carries a `department` tag for categorisation and surfacing in the app. Note (MVP simplification): on-chain voting is open to any address, one vote per address — citizen/department eligibility is a KYC/identity layer planned for national scale, not enforced in the MVP contracts. Committee opt-in is per-project, not per-department.

---

## 3. High-Level Architecture (in plain English)

DemocraFund is **six smart contracts** on Arbitrum that together replace the trust you'd normally place in a single administrator with rules anyone can inspect. The design rule that drives everything: **no single person — not even the admin — can move a single token by themselves.**

```
  PaymentToken (GES)      <- the "shadow rand", minted per project
       |
  ProjectFactory          <- one stop for creating tenders + the mint authority
       |
  ProjectGovernance       <- ONE per tender: lifecycle + voting + award
       |
  ProjectEscrow           <- ONE per awarded project: the money vault +
                              milestone multisig (signatures, not keys)
       |
  CompanyRegistry         <- who is allowed to bid
       |
  Redemption              <- the off-ramp: burn GES, get fiat + receipt NFT
```

**The two tracks.** DemocraFund deliberately never custodies member money. Members' real dues stay in the club's real bank account — on-chain, members only carry *identity* (whose vote, whose signature). The only money that ever touches the chain is (a) the exact budget of an awarded project and (b) the builder's payment for it, in a token that looks and behaves like a stablecoin ("GES") and is later redeemed back into real money.

**The trustless core.** When a tender is awarded, the money is minted into a **milestone-gated multisig escrow** — a vault that pays out in stages, and only when the right people cryptographically sign that a stage is done: the admin, the builder, **and** at least one community member drawn at random (Chainlink VRF). Nobody — not the admin, not the builder, not the members alone — can unlock a stage. Cancelling a project is deliberately *harder* than paying a stage.

**What the citizen sees.** A member votes on which builder wins, can opt into the committee pool, and (if drawn) approves work-in-progress with one tap in the app. Every vote, every signature, every payment is on a public block explorer. The committee even earns a small token fee per milestone they sign — compensation for the oversight work, pulled by the member themselves.

---

## 4. End-to-End Lifecycle

1. **Tender creation** — Admin posts a tender (e.g. "Upgrade the entrance area") with a brief, budget ceiling, department tag, and supporting docs uploaded to IPFS. Tender is now publicly visible on-chain (hash + metadata) and in the app.
2. **Proposal submission** — Registered companies submit proposals: price, timeline, plan/docs (IPFS), broken into **milestones/stages** with a payment amount per stage. The milestone schedule must sum exactly to the bid price.
3. **Citizen voting** — Members view all proposals and vote for one. One member, one vote, recorded on-chain. Voting window has a defined, time-enforced close time — the admin cannot close it early.
4. **Shortlist** — The top `n` proposals by vote count (admin sets `n` at close of voting; boundary ties all pass) are surfaced to Admin.
5. **Government award** — Admin selects the winner **from the shortlist** (not necessarily #1; the contracts verify the awarded proposal was in the top-`n` by votes). This preserves legitimate government discretion while making an off-list, unvoted choice impossible. The award is only possible until `awardDeadline`; after it, anyone can expire the tender (nothing was funded yet).
6. **Escrow creation & funding** — On award, an escrow contract is deployed for this specific project, funded with the agreed budget **plus the committee fee reserve** in GES. The awarded proposal's payment wallet becomes the builder signer.
7. **Committee formation** — 1 admin representative + members drawn from the project's opted-in pool:
   - **Pool of 0:** no community committee — 2-of-2 fallback (admin + builder).
   - **Pool of 1–3:** everyone serves directly — no randomness needed.
   - **Pool of 4+:** a Chainlink VRF draw picks **3 members + 2 alternates**. Until the coordinator responds, no approvals are possible.
8. **Milestone execution loop** (repeats per stage):
   - Builder marks a stage complete + uploads evidence (photos, invoices) to IPFS; the evidence hash is locked on-chain **before** any approval can exist.
   - Each signer independently inspects/confirms and signs (EIP-712 typed messages, submitted in batches by anyone — a relayer).
   - At the derived threshold — **admin AND builder plus ≥1 member, ≥3 signatures total when M≥1** — the escrow auto-releases that stage's payment to the builder's payment wallet. Members can never band together to approve.
   - A committee fee credit accrues to every member who signed the released milestone; members pull it themselves via `collectFees()` (no deadline).
9. **Project completion** — Final stage released, the project is marked complete, and the un-owed fee reserve is swept back to the treasury. The full history (tender → proposals → votes → award → every milestone signature → every fund movement) remains permanently viewable.
10. **Off-ramp** — The builder redeems their GES: the tokens are burned, a transferable receipt NFT is minted as proof, and the paying authority releases the real money to the builder's KYC'd bank account and marks the receipt `paid` on-chain.

---

## 5. Money Flows (every path, tracked end to end)

### 5.1 The accounting identity

Every escrow obeys one invariant, checked on every fund movement:

```
balance + totalReleased + settlementPaid + feesCollected
       + totalReturnedOnCancellation + totalSweptToTreasury
       == totalProjectBudget + feeReserve
```

In words: **whatever the escrow holds plus everything that ever left it equals exactly what was funded.** Because the fee reserve covers the maximum possible fee liability, the escrow can never hold less than what members are still owed. The invariant fuzzers assert this continuously.

### 5.2 Flow 1 — Award funding (mint)

At award, the factory mints `cost + feeReserve` straight into the project's escrow:

- `cost` — the winning bid, exactly the sum of the milestone schedule.
- `feeReserve = milestones.length × 3 × committeeFeePerSignature` — the *maximum* fee liability (a full 3-member committee signing every milestone). It is funded upfront because the drawn committee size is unknown while the VRF draw is pending.

Only a registered project's own governance can trigger the mint, and only up to `budgetCap + feeReserve`.

### 5.3 Flow 2 — Milestone release (the only way the builder gets paid on schedule)

```
signatures (admin + builder + ≥1 member) --> escrow verifies thresholds
        |
        v
escrow transfers milestone.amount --> builder's payment wallet
        |
        v
fee credit accrues to each signing member --> members pull via collectFees()
```

The transfer happens **inside the same transaction** as the signature submission — there is no second step where funds could be stalled. The builder's wallet was fixed at award (the company's registered payment wallet); nobody can redirect it.

### 5.4 Flow 3 — Committee fees

Fees are pull-based and cannot be bricked by anyone:

- **Accrual** (release time): pure storage write, no external calls — nobody's wallet can block a release.
- **Collection** (`collectFees()`): the member pulls exactly their credit. Works after cancellation too, with no deadline.
- **Funding** comes from the `feeReserve` minted at award — fees never reduce what the builder receives.
- Zero fee disables the mechanism entirely. Fees are never accrued for the deposit, on unreleased milestones, or to admin/builder/alternates.

### 5.5 Flow 4 — Cancellation / abort (the only ways money returns before completion)

| Path | Trigger | What happens |
|---|---|---|
| **Signature cancellation** | M+1-of-M+2 signatures with a shared public `reasonHash` | Escrow cancelled; treasury refunded `balance - totalUncollectedFees` (members' uncollected fees stay payable forever) |
| **Abort (pending draw)** | Admin anytime while the VRF draw is pending; anyone after 7 days | Same refund — with no fees accrued yet, it's the full balance |
| **Pre-award cancellation** | Admin | No escrow exists yet — pure lifecycle cleanup |
| **Expired deliberation** | Anyone after `awardDeadline` passes | Tender cancelled, nothing was ever funded |

Cancellation requires **one more** signature than a release — the same bare majority that approves progress can never terminate the project.

### 5.6 Flow 5 — Completion sweep

When the last milestone releases, the fee liability is final. `completeProject` (permissionless — the release history is the proof) sweeps the escrow's **un-owed** surplus — `balance - totalUncollectedFees` — to the treasury. Computing the surplus from the live balance (not from the reserve formula) makes the sweep idempotent: a second call can never drain what members are owed.

### 5.7 Flow 6 — Settlement

The admin can pay the builder a partial compensation (`releaseSettlement`) — e.g. negotiated payment for work done before a cancellation finalises. Capped at `budget - released - settled`, which is provably below the balance left after reserving uncollected fees, so settlements can never dip into the fee money.

### 5.8 Flow 7 — Off-ramp (burn -> receipt -> fiat)

```
builder approves GES --> Redemption.redeem()
        |
        v
GES burned (supply down, peg preserved) + receipt NFT minted (Pending)
        |
        v
paying authority honours the fiat payout --> markPaid(tokenId, payoutRef)
        |
        v
receipt NFT now shows Paid - the permanent audit trail of the burn
```

The receipt is the terminal artifact of the token's lifecycle — mint -> escrow -> milestone -> burn -> fiat — and the seed of the future builder track record. It is transferable (the state follows the token, not the owner) and fully on-chain.
---

## 6. Technical Architecture (for developers)

### 6.1 Contract inventory

| Contract | Purpose | Deployment model | Key state |
|---|---|---|---|
| **PaymentToken** (`src/PaymentToken.sol`) | ERC-20 "Generic Example Stable" (GES), behaves like a stablecoin | One, deployed first | `FACTORY` role (mint + burn) |
| **CompanyRegistry** (`src/CompanyRegistry.sol`) | Permissionless company self-registration | One, deployed before the factory, injected into every governance | `companies[]`, `companyIdOfAdmin`, `companyCount` |
| **ProjectFactory** (`src/ProjectFactory.sol`) | Creates tenders; the sole mint authority; global policy + shared VRF config | One | `isProject[]`, `CREATE_PROJECT_ROLE`, duration minimums, `vrfConfig` |
| **ProjectGovernance** (`src/ProjectGovernance.sol`) | Per-tender lifecycle state machine + voting + committee draw | `new` per project (not a clone — inherits `VRFConsumerBaseV2Plus`, coordinator injected in the constructor) | lifecycle enum, deadlines, proposals, votes, opt-in pool, escrow pointer |
| **ProjectEscrow** (`src/ProjectEscrow.sol`) | Milestone-gated multisig vault; source of truth for ALL fund movement | Minimal-proxy **clone**, initialized by governance at award | milestone schedule, signature bitmaps, per-purpose nonces, fee credits, accounting counters |
| **Redemption** (`src/Redemption.sol`) | Off-ramp: burn GES -> receipt NFT -> paying authority attestation | One | `receipts[]`, `PAYER_ROLE`, `receiptCount` |

### 6.2 Design decisions that matter

- **The escrow owns the money.** Governance owns the lifecycle and committee selection only. The escrow's milestone storage is the source of truth for releases; governance's `Proposal.milestones` mirrors it for history. Never reintroduce release logic in governance.
- **Signatures, not keys.** The escrow is a multisig that verifies **EIP-712 typed digests** via OZ `SignatureChecker` (EOA + ERC-1271 smart wallets — the account-abstraction future). A relayer (anyone) submits batches; one transaction can carry the whole committee. There is no privileged "signer key" in the contract.
- **Per-purpose nonces.** Nonces are keyed per (signer, milestone), per (signer, cancellation), per (signer, promotion) — not one counter. Pre-signed batches for different milestones never collide; replay is still impossible.
- **Derived thresholds, never hardcoded.** The release and cancellation rules derive from the actual drawn committee size M:

  | M | Signers | Milestone release | Cancellation |
  |---|---|---|---|
  | 3 | 5 | 3-of-5: admin + builder + ≥1 member | 4-of-5 |
  | 2 | 4 | 3-of-4: admin + builder + ≥1 member | 3-of-4 |
  | 1 | 3 | 3-of-3 (everyone) | 2-of-3 |
  | 0 | 2 | 2-of-2 (admin + builder) | 2-of-2 |

- **Committee addresses are NEVER admin-supplied** — only from the opt-in pool (VRF draw, or all opt-ins when pool ≤ 3). A stalled member can be replaced by an alternate via signature-gated `promoteAlternate`, which mirrors the release rule and clears the replaced slot's signature bits.
- **Time is enforced, not advisory.** `proposalDeadline`, `votingDeadline`, `awardDeadline` are checked on-chain. The `urgent` bypass flag was deliberately removed. A pending VRF draw cannot lock funds: after `SELECTION_RETRY_DELAY` (7 days) anyone can `retryCommitteeSelection` or abort via `cancelProject`.
- **No external calls in the release path.** Fees accrue as pure storage; a member's wallet can never brick a release.
- **Money can never be stuck.** Every terminal state has a defined money outcome: cancellation refunds the treasury (`balance - uncollected fees`), completion sweeps the un-owed surplus, uncollected fees remain collectable forever, and off-ramping is permissionless.

### 6.3 The escrow's EIP-712 signature scheme

Signers sign typed digests; relayers submit them in batches. The three purposes:

| Purpose | Typehash | Nonce scope |
|---|---|---|
| Milestone approval | `MilestoneApproval(uint256 milestoneIndex,bytes32 evidenceHash,uint256 nonce)` | `milestoneNonces[signer][milestone]` |
| Cancellation | `CancellationApproval(bytes32 reasonHash,uint256 nonce)` | `cancellationNonces[signer]` |
| Alternate promotion | `AlternatePromotion(uint256 alternateIndex,uint256 memberIndex,uint256 nonce)` | `promotionNonces[signer]` |

Each signer occupies a **bitmap slot**: 0 = admin, 1..M = members, M+1 = builder. A promotion clears the replaced member's bits in the current milestone and cancellation bitmaps so the newcomer signs fresh. OZ `EIP712` recomputes the domain separator per clone automatically — no manual caching.

### 6.4 Lifecycle state machine

```
CREATED --> PROPOSAL --> VOTING --> DELIBERATION --> AWARDED --> COMPLETE
                  |          |           |
                  |          |           +---> CANCELLED (expired deliberation)
                  |          +---> (admin cancel) --> CANCELLED
                  +---> (admin cancel) --> CANCELLED
AWARDED ---> CANCELLED (escrow abort / signature cancellation finalised)
```

Transitions are admin-driven except: `expireDeliberation` (anyone after `awardDeadline`), `completeProject` (anyone, once all milestones released), and `cancelProject` finalisation (anyone once the escrow's signature cancellation fired, or anyone after 7 days with a pending draw).

---

## 7. Contract Interaction Flows

### 7.1 Tender creation

```
Admin (CREATE_PROJECT_ROLE) --> ProjectFactory.createProject(config)
        |
        +-- validates: durations >= platform minimums, budgetCap > 0,
        |               fee <= 1000, hashes present, VRF config sane
        +-- deploys ProjectGovernance(config, VRF config, escrow impl, token, registry)
        +-- registers it in isProject[]
        +-- governance grants DEFAULT_ADMIN_ROLE to governanceSafeWallet
```

### 7.2 Bid + vote

```
Company admin (registered & active) --> ProjectGovernance.createProposal(companyId, ...)
        |
        +-- registry lookup: msg.sender must be companyId's adminWallet
        +-- one proposal per company per tender
        +-- milestones must sum to the bid cost, <= budgetCap

Member --> optInForCommittee()  (pool membership, PROPOSAL..DELIBERATION)
Member --> voteForProposal(id)  (one vote per address, before votingDeadline)

Admin --> closeProposalsAndOpenVoting()   (only after proposalDeadline)
Admin --> closeVoting(n)                  (only after votingDeadline; fixes shortlist size n)
```

### 7.3 Award — three committee paths

```
Admin --> awardProposal(id)
        +-- must be in the top-n shortlist by votes (_requireInShortlist, ties pass)
        +-- clones + initializes ProjectEscrow (schedule, fee reserve, signer wallets)
        +-- factory mints cost + feeReserve into the escrow
        +-- committee formation:
              pool 0    -> setCommitteeMembers([], [])              (2-of-2 fallback)
              pool 1-3  -> setCommitteeMembers(allOptedIn, [])      (no VRF)
              pool 4+   -> _requestCommitteeSelection() -> VRF draw
                           (3 members + 2 alternates, collision-safe picks,
                            numWords = min(pool, 5))
        +-- if depositRequired: releaseDeposit() (milestone 0 auto-releases,
            evidence = bytes32("Deposit"), no committee signatures, no fees)
```

### 7.4 Milestone release (the daily loop)

```
Builder --> submitMilestoneComplete(evidenceHash)      [locks evidence; counts as their signature]
Relayer --> approveMilestone(Signature[])              [batch of EIP-712 sigs]
        +-- builder-first enforced (BuilderMustSubmitFirst)
        +-- builder can never sign here (BuilderMustSubmitDirectly)
        +-- thresholds derived from M (see 6.2)
        +-- release fires INSIDE this tx: transfer + fee accrual
```

### 7.5 Cancellation, promotion, completion, off-ramp

```
Cancellation:   approveCancellation(reasonHash, Signature[])
                -> M+1-of-M+2; reasonHash locked after first sig (ReasonMismatch)
                -> refund = balance - totalUncollectedFees

Promotion:      promoteAlternate(altIndex, memberIndex, Signature[])
                -> mirrors the release rule; clears replaced slot's bits

Completion:     completeProject()  (permissionless)
                -> sweepSurplusToTreasury() = balance - totalUncollectedFees
                -> lifecycle COMPLETE

Off-ramp:       Redemption.redeem(amount, destinationId, escrow)
                -> PAYER_ROLE.markPaid(tokenId, payoutRef) after the fiat transfer
```

---

## 8. Worked Examples

### 8.1 Simple example — small club project, no committee (M = 0)

Humewood's committee posts "Replace the clubhouse boiler" with `budgetCap = 1,000 GES`. Nobody opts in for the committee (M = 0), so the escrow runs the **2-of-2 fallback**.

1. **Bid.** "Boilers R Us" registers a company (adminWallet + paymentWallet), bids `1,000 GES` with 2 milestones: `[400, 600]`.
2. **Vote.** 30 members vote; the proposal wins the shortlist.
3. **Award.** The admin awards it. The factory mints `1,000 + 2×3×10 = 1,060 GES` into the new escrow (the extra 60 is the fee reserve — never owed here, returned at completion). Committee is finalised empty -> 2-of-2.
4. **Milestone 1.** The builder submits photos of the new boiler (`evidenceHash` locked). The relayer submits the admin's signature. Threshold: admin + builder = 2-of-2 -> **400 GES transfers to the builder's payment wallet**.
5. **Milestone 2.** Same flow -> **600 GES released**.
6. **Completion.** All milestones released. `completeProject()` sweeps the un-owed 60 GES back to the treasury.
7. **Off-ramp.** The builder redeems 1,000 GES: burned, receipt NFT minted, paying authority releases R1,000 to their bank account and marks the receipt `paid`.

**Money at the end:** builder got 1,000; treasury got back 60; the escrow is empty; total supply minted = 1,060, burned = 1,000.

### 8.2 Complex example — VRF committee, stall, promotion, fees, cancellation

Humewood posts "Entrance upgrade" (`budgetCap = 5,000 GES`, `committeeFeePerSignature = 10`). Six members opt in.

1. **Award with a draw.** Two companies bid; proposal A (`3,000 GES`, milestones `[900, 900, 1,200]`) wins the vote. On award the escrow is minted `3,000 + 3×3×10 = 3,090 GES` and a VRF request fires (`numWords = min(pool, 5) = 5`).
2. **Fulfilment.** The coordinator delivers randomness; the draw picks members 100, 101, 102 and alternates 103, 104. The escrow finalises. **No approvals were possible while the draw was pending.**
3. **Milestone 1.** Builder submits evidence. Admin, member 100 and member 101 sign -> 3-of-5 with admin + builder + ≥1 member -> **900 GES released**. Members 100 and 101 each accrue a 10 GES fee credit.
4. **Stall.** Member 102 doesn't respond for weeks. The relayer gathers promotion signatures (admin + builder + member 100) -> `promoteAlternate(0, 2, sigs)` swaps alternate 103 into member slot 2, clearing member 102's signature bits. No re-draw needed; M stays 3.
5. **Milestone 2.** Builder submits; admin + member 101 + the new member 103 sign -> **900 GES released**. Fees accrue to 101 and 103. Member 100 pulls their 10 GES via `collectFees()`.
6. **Dispute.** The committee discovers substandard materials. Four signatures (4-of-5: admin + builder + two members) commit to one `reasonHash` ("substandard materials, photos in evidence"). The escrow cancels and refunds the treasury `balance - totalUncollectedFees` — members' uncollected fee credits stay payable.
7. **Finalisation.** Anyone calls `governance.cancelProject()` -> lifecycle CANCELLED. The audit trail shows every vote, every signature, every release, and the cancellation reason.

**Money at the end:** builder received 1,800 (milestones 1+2); the remaining 1,200 milestone was never paid; members collected (or can still collect) their 10 GES each; the treasury got back everything else. No token was ever released without the required signatures.

---

## 9. Access Control (who can do what)

Roles come from OpenZeppelin `AccessControl`; everything else is enforced by modifiers, caller checks, EIP-712 signatures, or on-chain state (lifecycle, deadlines, thresholds).

### 9.1 Actors

| Actor | Identity | Powers |
|---|---|---|
| **Platform admin** | `DEFAULT_ADMIN_ROLE` on `PaymentToken`, `ProjectFactory`, `Redemption` (the deployer) | Grants the `FACTORY` mint/burn roles; updates the global minimum voting duration; grants `PAYER_ROLE`. |
| **Paying authority** | `PAYER_ROLE` on `Redemption` | Marks redemption receipts paid or rejected after honouring the fiat payout. |
| **Project creator** | `CREATE_PROJECT_ROLE` on `ProjectFactory` | Creates tenders (one governance contract per project). |
| **Project admin** | `DEFAULT_ADMIN_ROLE` on each `ProjectGovernance` (the project's `governanceSafeWallet` — intended to be a Safe multisig) | Drives the lifecycle: opens windows, closes voting, awards, settles, cancels pre-award. |
| **Companies** | Registered in `CompanyRegistry`; the `adminWallet` acts for the company | Bid on tenders (one proposal per company per tender); update their own payment wallet/infoHash/active flag. |
| **Citizens** | Any EOA | Opt into the committee pool; vote once per tender; relayer signatures. |
| **Committee signers** | Admin (slot 0), members (slots 1..M), builder (slot M+1) | Approve milestone releases and cancellations via EIP-712 signatures. |
| **Relayer** | Anyone | Submits signature batches to the escrow (no permissions — the signatures are the credentials). |
| **VRF coordinator** | The configured Chainlink coordinator | The only caller allowed to invoke `fulfillRandomWords` (enforced by `VRFConsumerBaseV2Plus`). |

### 9.2 PaymentToken

| Function | Caller | Enforcement |
|---|---|---|
| `mint(to, amount)` | holder of `FACTORY` role | `onlyRole(FACTORY)`. Only the factory and Redemption are ever granted it. |
| `burn(from, amount)` | holder of `FACTORY` role | `onlyRole(FACTORY)`. Redemption is the only intended burner. |
| `setFactoryRole(factory)` | `DEFAULT_ADMIN_ROLE` | One-time wiring at deploy. |

The token has **no pause, no blacklist**. The factory only mints the awarded cost **plus the fee reserve** into the caller's own escrow (`mintInitialSupplyForProject`, bounded by `budgetCap + escrow.feeReserve()`). Redemption is the **only burner** — burning happens exclusively as proof-of-burn at off-ramp, keeping the peg 1:1 with the real-world reserve.

### 9.3 ProjectFactory

| Function | Caller | Enforcement |
|---|---|---|
| `createProject(config)` | `CREATE_PROJECT_ROLE` | `onlyRole(CREATE_PROJECT_ROLE)`. |
| `mintInitialSupplyForProject(escrow, amount)` | a registered project governance | `isProject[msg.sender]` **and** `msg.sender.projectEscrow() == escrow` **and** `amount <= budgetCap + escrow.feeReserve()`. |
| `updateGlobalMinimumVotingDuration(x)` | `DEFAULT_ADMIN_ROLE` | `onlyRole(DEFAULT_ADMIN_ROLE)`. |

### 9.4 ProjectGovernance

**Admin-only** (`DEFAULT_ADMIN_ROLE`, granted to `governanceSafeWallet` in the constructor):

| Function | Note |
|---|---|
| `acceptProposals` | CREATED -> PROPOSAL |
| `closeProposalsAndOpenVoting` | only after `proposalDeadline` |
| `closeVoting(n)` | only after `votingDeadline`; fixes the shortlist size and `awardDeadline` |
| `awardProposal(id)` | lifecycle DELIBERATION, `now <= awardDeadline`, inside the top-`n` shortlist by votes (`_requireInShortlist`) |
| `releaseSettlement(amount)` | forwarded to the escrow, which enforces its own cap |
| `cancelProject` (pre-award / pending-draw paths) | see the time-based exceptions below |
| `retryCommitteeSelection` | admin may retry immediately |

**Permissionless** (no role, bounded by state):

| Function | Bound by |
|---|---|
| `voteForProposal(id)` | lifecycle VOTING, `now < votingDeadline`, one vote per address |
| `optInForCommittee` | lifecycle PROPOSAL/VOTING/DELIBERATION, not the `governanceSafeWallet`, once per address |
| `createProposal(companyId, ...)` | **not role-based** — caller must be the company's registered `adminWallet`, the company must be `active`, one proposal per company per tender, plus lifecycle/deadline/cost checks |
| `completeProject` | lifecycle AWARDED + all milestones released (proof is on-chain) |
| `expireDeliberation` | lifecycle DELIBERATION + `now > awardDeadline` — anyone can cancel a tender the admin never awarded |
| `retryCommitteeSelection` | any caller once `now >= selectionRequestedAt + SELECTION_RETRY_DELAY` (7 days) |
| `cancelProject` | any caller once the escrow's signature-based cancellation has fired (committee finalised), or once `SELECTION_RETRY_DELAY` has passed with the draw pending |

**Coordinator-only:**

| Function | Enforcement |
|---|---|
| `fulfillRandomWords(requestId, words)` | `VRFConsumerBaseV2Plus.rawFulfillRandomWords` verifies `msg.sender == s_vrfCoordinator` before calling this override. No one else can deliver randomness. |

### 9.5 ProjectEscrow

The escrow has **no roles**. Access is either `onlyGovernanceContract` (modifier comparing `msg.sender` to the governance that initialized the clone) or cryptographic (EIP-712 signatures + `SignatureChecker`, supporting EOAs and ERC-1271 wallets).

| Function | Caller | Notes |
|---|---|---|
| `initialize(...)` | the clone's creator (governance at award time) | Any address may initialize a fresh clone they deploy themselves; the implementation contract has initializers disabled. `msg.sender` becomes `projectGovernanceContract`. |
| `setCommitteeMembers(members, alts)` | `onlyGovernanceContract` | Once only; flips `committeeFinalized`. Called by governance (directly or from the VRF callback). |
| `submitMilestoneComplete(evidence)` | the builder signer (`builderSigner` = winning company's payment wallet) | Counts as the builder's signature; locks evidence. |
| `approveMilestone(sigs)` | anyone (relayer) | Each signature verified against the signer's bitmap slot; the **builder cannot** sign here (`BuilderMustSubmitDirectly`). Release fires automatically at admin AND builder AND ≥1 member (≥3 total when M≥1; 2-of-2 when M=0). |
| `approveCancellation(reason, sigs)` | anyone (relayer) | Signatures from any of the M+2 signers; threshold M+1-of-(M+2) (2-of-2 fallback). All commit to the same locked `reasonHash`. |
| `promoteAlternate(alt, member, sigs)` | anyone (relayer) | Rule mirrors release: admin AND builder AND ≥1 member when M≥2 (admin+builder when M=1). The promoted alternate takes the slot; its bits are cleared. |
| `releaseDeposit` | `onlyGovernanceContract` | Award-time deposit; exempt from `committeeIsFinalized` by design. |
| `abort` | `onlyGovernanceContract` | Pre-finalization refund to treasury; governance gates it admin-first, then anyone after `SELECTION_RETRY_DELAY`. |
| `releaseSettlement(amount)` | `onlyGovernanceContract` | Capped by `totalProjectBudget - totalReleased - settlementPaid`. |
| `collectFees` | any member with a credit | Pull-based; no collection deadline. |
| `sweepSurplusToTreasury` | `onlyGovernanceContract` | Called by `completeProject`; sweeps the un-owed reserve (idempotent: live balance minus outstanding credits). |
| Views (`hasSigned`, digest getters, `domainSeparator`, ...) | anyone | Read-only; the digest getters embed the signer's current per-purpose nonce. |

**Signer slots** (who can hold a signature credential):

- Slot 0 — admin: the project's `governanceSafeWallet` (set at initialize).
- Slots 1..M — committee members: drawn from the opt-in pool only (VRF, or all opt-ins when pool ≤ 3); never admin-supplied. Replaced only via `promoteAlternate` (from the alternates list).
- Slot M+1 — builder: the winning company's `paymentWallet`.
- Alternates: not signers until promoted.
- Committee fee **credits** accrue only to members who signed a *released* milestone — never to admin, builder, or alternates.

### 9.6 CompanyRegistry

No roles; authority comes from registration state.

| Function | Caller |
|---|---|
| `registerCompany(paymentWallet, infoHash)` | any address; becomes the company's `adminWallet`. One company per wallet (`AlreadyRegistered`). |
| `updateCompany(paymentWallet, infoHash)` | the company's `adminWallet` (`companyIdOfAdmin[msg.sender]`). |
| `setCompanyActive(bool)` | the company's `adminWallet`. |

### 9.7 Trust model & centralisation points

1. **Platform admin** (deployer) holds `DEFAULT_ADMIN_ROLE` on the token and the factory: can grant mint authority and change the global voting floor. It cannot interfere with existing projects (it has no governance roles).
2. **Project admin** (`governanceSafeWallet`, intended to be a Safe multisig) is the strongest per-project actor: opens/closes windows, chooses the winner **within the vote-bound shortlist**, can settle and cancel. Time-enforced boundaries (`proposalDeadline`, `votingDeadline`, `awardDeadline`, `SELECTION_RETRY_DELAY`) ensure no single wallet can stall or force a tender past its deadlines.
3. **Committee members are never admin-chosen** — the opt-in pool + VRF draw is the only path, and the award is bound to citizen votes.
4. **The escrow never trusts callers, only signatures** — the relayer model means any party (or no party) can run the frontend/backend; credentials are the signers' EIP-712 signatures, replay-protected by per-purpose nonces.

---

## 10. Dispute Resolution (built vs documented)

Some of this is already implemented in the MVP contracts; the rest is specified so it can be pointed to honestly as "solved on paper, next to build" rather than an unnoticed gap.

- **Stalled signer.** A citizen or official signer doesn't respond within a defined window (e.g. 7 days).
  - Citizen signer: **implemented** via `promoteAlternate` — any relayer can submit a promotion (admin AND builder AND ≥1 remaining member must sign) that swaps the stalled member for an alternate from the same VRF draw, clearing the stale slot's signature bits. The alternate replaces the member outright rather than requiring a fresh redraw.
  - Redraw from the pool (fresh VRF request) as an alternative replacement mechanism: roadmap.
  - Admin/official signer: there's only one, so a timeout can't just redraw. Partially mitigated by the time-enforced award deadline and the 7-day permissionless VRF retry/abort window; a designated deputy-admin role is flagged as an open design question.
- **Contested milestone.** A signer disagrees that a stage is complete. **Not yet implemented** — any **reject** vote would require a written reason plus supporting evidence (photos, docs) uploaded to IPFS, visible to everyone alongside approve votes. This would give a bad-faith rejection the same public accountability cost as a bad-faith approval.
- **Builder abandonment / breach.** **Implemented** as cancellation: a deliberately higher-threshold action — **4-of-5 normally** (M+1-of-M+2, never reachable by the release majority) — from the same M+2 committee members, redirecting the remaining escrow balance back to the club treasury. Requires a mandatory public on-chain justification (`reasonHash`) locked after the first signature. Making this threshold harder to reach than a normal release is intentional: terminating a builder is a heavier action.
- **Process appeals.** No path exists if someone believes a signer replacement or a rejection was itself unfair. A genuine open gap; a mature version likely needs a member-jury appeal mechanism.

---

## 11. Testing & Test Coverage

The contracts ship with **137 tests across 7 suites** — unit, fuzz, invariant, and end-to-end flows — plus property-based invariant fuzzing that runs continuously in CI.

### 11.1 Test suites

| Suite | What it covers |
|---|---|
| `test/ProjectEscrow.t.sol` | Release rules per M, signature correctness (incl. ERC-1271), cancellation, fees (accrual + collection + sweeps), promotion, settlement, redemption, events, revert guards |
| `test/Governance.t.sol` | Shortlist binding, deadlines/expiry, VRF timeout paths, proposal rules, factory guards, access control |
| `test/TokenAndRedemption.t.sol` | Token access control + redemption edge cases |
| `test/Fuzz.t.sol` | Property tests with `bound()` (release-rule derivation, schedule validation, replay/nonce safety, VRF draw invariants) |
| `test/Invariants.t.sol` | Escrow accounting invariants driven by a randomized action handler (submit/approve/cancel/promote/settle/collect/sweep) |
| `test/GovernanceInvariants.t.sol` | Lifecycle state-machine invariants driven by a self-contained handler |
| `test/Flows.t.sol` | End-to-end journeys: happy path with VRF, cancellation, deposit, multi-company, expiry |

Invariant fuzzing runs **128 runs × 100 actions** per invariant; the suite also runs at heavier settings (256 × 300 = 76,800 random actions per invariant) with **zero reverts** — every handler action is legal, and the accounting invariants (`balance + released + settled + collected + returned + swept == budget + feeReserve`, balance never below owed fees, cancellation keeps fee funds) hold throughout.

### 11.2 Coverage (forge coverage, src/ only)

| Contract | Lines | Statements | Functions |
|---|---|---|---|
| CompanyRegistry | 100.00% (23/23) | 78.6% | 100% |
| PaymentToken | 100.00% (10/10) | 87.5% | 100% |
| ProjectEscrow | 98.42% (249/253) | 91.8% | 100% |
| ProjectFactory | 100.00% (46/46) | 90.3% | 100% |
| ProjectGovernance | 99.04% (207/209) | 88.5% | 100% |
| Redemption | 100.00% (48/48) | 94.4% | 100% |
| **Total (incl. test helpers)** | **94.61% (912/964)** | 89.7% | 95.2% |

The remaining uncovered lines are **defensive revert guards that are provably unreachable** in the current state machine (e.g. `AccountingMismatch`, "milestone already released" when `currentMilestoneIndex` can never point at a released milestone, and an impossible pending-draw branch). The revert guards that *are* reachable are each covered by an explicit `expectRevert` test (~70 assertions across the suite).

---

## 12. Gas Sponsorship (users never touch gas or sign anything)

Because members are fully custodial, the backend already holds their private key, so it can sign **and submit** every transaction on their behalf. A member clicking "Vote" or "Approve stage" never sees a wallet, a signature prompt, or a gas fee.

The only real requirement: whichever address submits a transaction needs native ETH for gas. MVP approach:

- Backend maintains a funded **treasury wallet**.
- Before submitting a transaction for a member, the backend checks their custodial wallet's ETH balance; if insufficient, it auto-top-ups a small amount from the treasury first. Entirely invisible to the user.

Two more sophisticated patterns are roadmap items (see ENDGAME.md):

- **Meta-transactions (EIP-2771 / Gas Station Network)** — the standard fix *when users self-custody*: they sign off-chain, a relayer submits and pays gas. Not needed yet since custody already solves signing, relevant the moment DemocraFund offers self-custody.
- **ERC-4337 Account Abstraction + Paymaster** — the production-grade answer for national scale: smart-contract wallets, sponsored gas, no dependence on one backend being the sole custodian of every key.

Each member still gets a distinct, real on-chain address even though the backend holds the key, so every vote and every milestone signature remains cryptographically attributable to a specific person.

---

## 13. Deployment

The deploy script (`script/Deploy.s.sol`) deploys the full stack against **Arbitrum Sepolia** with the real Chainlink VRF v2.5 configuration:

```
forge script script/Deploy.s.sol:Deploy --rpc-url $ARB_SEPOLIA_RPC --broadcast
```

Before the demo, at vrf.chain.link: create + fund a subscription, and register each project's governance contract as a consumer (`registerConsumer` helper in the script). Verify the coordinator/keyhash against docs.chain.link/vrf/v2-5/supported-networks before any real deployment. The `subscriptionId` in the script is a TODO to fill in.

---

## 14. The Endgame

The MVP is the pilot proof. The national-scale vision — real fiat rails, self-custody wallets, KYC-scoped voting, multi-department municipalities, builder track records, dispute resolution — is fully documented in **[ENDGAME.md](./ENDGAME.md)**.
