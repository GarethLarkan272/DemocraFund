# AGENTS.md

Foundry/Solidity repo: on-chain public tendering with citizen voting and milestone-gated multisig escrow (product vision in `README.md` — treat the contracts as the source of truth for behavior).

## Commands
- `forge build` / `forge test` — compile and run the suite (117 tests: unit + fuzz + invariant + end-to-end flows)
- `forge fmt` — **required before finishing**: CI runs `forge fmt --check` and fails otherwise (`.github/workflows/test.yml` also runs `forge build --sizes` + `forge test -vvv`; `via_ir = true` in foundry.toml)
- **solc is pinned to `0.8.26`** (`solc_version` in foundry.toml) — the pinned chainlink-evm v1.5.0 VRF mock uses a modifier-style base constructor call, a hard compiler error since 0.8.27 with no upstream fix. Don't bump solc (or the pragmas, currently `^0.8.26`) until chainlink-evm is upgraded. `[lint] lint_on_build = false` keeps `forge build`/`forge test` output clean; `forge lint` still reports the mock as an error (solar emits it as a hard diagnostic with no lint ID, and the `ignore` config is applied too late on forge < 1.4 — foundry-rs/foundry#12721) — ignore it. Our own code must stay lint-clean.
- `forge test --match-path test/Fuzz.t.sol --fuzz-runs 1000` — heavier fuzz verification (release-rule derivation, schedule validation, replay/nonce safety, VRF draw invariants)
- Invariant fuzzing config lives in `[invariant]` in foundry.toml (128 runs × depth 100 — tuned for the full-stack lifecycle handler).

## Test suite layout (test/)
- `TestBase.sol` — shared fixtures: full stack deployment (token, registry, factory, VRF mock, redemption), fixed signing keys (ADMIN_PK=1, BUILDER_PK=2, members 100+), helpers (`_deployProject`, `_deployAndAward`, `_newEscrow`, `_milestoneSigs`, `_cancellationSigs`, `_promotionSigs`, `_fulfill`, `toUint256Array`), plus `DummyGovernance` and `MockERC1271Wallet`.
- `ProjectEscrow.t.sol` — release rules per M, signature correctness (incl. ERC-1271), cancellation, fees, promotion, redemption, events.
- `Governance.t.sol` — shortlist binding, deadlines/expiry, VRF timeout paths, proposal rules, factory guards.
- `TokenAndRedemption.t.sol` — token access control + redemption edge cases.
- `Fuzz.t.sol` — property tests with bound() (NOTE: bound() wraps modulo — it does NOT clamp; tests must derive expected values from the bound result).
- `Invariants.t.sol` — escrow accounting invariants driven by `EscrowInvariantHandler` (random submit/approve/cancel/promote/settle/collect/sweep; admin/builder/alternates are real key-derived addresses).
- `GovernanceInvariants.t.sol` — lifecycle state-machine invariants driven by a self-contained handler.
- `Flows.t.sol` — end-to-end journeys: happy path with VRF, cancellation, deposit, multi-company, expiry.

## Architecture (not obvious from filenames)
- `ProjectFactory` deploys ONE `ProjectGovernance` per project via `new` — **not a clone**, because it inherits Chainlink's `VRFConsumerBaseV2Plus` (coordinator injected in constructor). `ProjectEscrow` IS a minimal-proxy clone, initialized by governance.
- `ProjectGovernance` owns the lifecycle state machine and committee selection only. `ProjectEscrow` owns the milestone schedule and ALL fund movement — the escrow's milestone storage is the source of truth; governance's `Proposal.milestones` mirrors it for history. Don't reintroduce release logic in governance.
- `PaymentToken`: admin-minted ERC-20; the factory holds the `FACTORY` role for mint, and the `Redemption` contract holds it for burn (the only burner — proof-of-burn off-ramp). Cancellation refunds the treasury instead of burning.
- **`Redemption`** (off-ramp): `redeem(amount, destinationId, escrow)` pulls GES from the caller, burns it, and mints a transferable ERC-721 receipt NFT (redeemer, escrow provenance, amount, destination hash, Pending/Paid/Rejected state). `PAYER_ROLE` (paying authority) calls `markPaid(tokenId, payoutRef)` / `markRejected(tokenId, reason)` to certify the fiat payout on-chain. Receipts are the terminal artifact of a token's lifecycle (mint → escrow → milestone → burn → fiat) and the future builder-track-record primitive. Implemented in `src/Redemption.sol`.
- **`CompanyRegistry`** (self-registration, deployed by the deploy script): each company stores `adminWallet` (the on-chain identity), `paymentWallet` (receives milestone payouts), `infoHash` (hash of off-chain docs), `active` (false = deregistered, cannot bid), and a sequential `companyId`. One admin wallet == one company (`companyIdOfAdmin`); admin can update paymentWallet/infoHash and toggle `active` (`setCompanyActive`). `createProposal` takes `companyId` only — governance looks up the registry, requires `msg.sender == adminWallet` AND the company to be active, and uses `paymentWallet` as the proposal's fundWallet (which becomes the escrow's builder signer if awarded). Deployed before the factory, passed into it, and forwarded to every governance contract.
- **Committee fees** (pull-based, upfront-funded): each project config sets `committeeFeePerSignature` (hard-capped at 1000 GES in the factory AND governance). At award the escrow is minted the budget PLUS a fee reserve (`milestones.length × 3 × fee` — the maximum possible liability, since the drawn committee size is unknown while the VRF draw is pending). When a milestone actually releases, a fee credit accrues to every committee member who signed it — pure storage, NO external calls in the release path, so nobody's wallet can brick a release — and members pull what they owe via `collectFees()` (no collection deadline). The escrow's accounting identity is `balance + totalReleased + settlementPaid + feesCollected + totalReturnedOnCancellation + totalSweptToTreasury == totalProjectBudget + feeReserve`; every fund movement preserves it, so the balance never drops below outstanding fee credits. Cancellation/abort refunds the treasury only `balance - totalUncollectedFees` — uncollected fees stay payable after termination. Zero fee disables accrual. Never accrued for the deposit, on unreleased milestones, or to admin/builder/alternates. Un-owed reserve surplus returns to the treasury on cancellation, and on completion `completeProject` sweeps it via `sweepSurplusToTreasury` (computed from the live balance minus outstanding credits, so it is idempotent).

## Invariants that must never break (trustlessness is the product)
- Release rule: admin AND builder AND ≥1 community member must sign, with ≥3 total when M≥1; M=0 (no committee) falls back to 2-of-2. Thresholds are derived from `memberSigners.length`, never hardcoded.
- Cancellation: `M+1`-of-`(M+2)` (4-of-5 normally, 2-of-2 fallback). All cancellation signatures commit to one shared `reasonHash`, locked after the first signature.
- Builder declares completion first: `submitMilestoneComplete(evidenceHash)` locks the evidence; approvals before it revert (`BuilderMustSubmitFirst`).
- Nothing works before `setCommitteeMembers` flips `committeeFinalized` (approvals, cancellation). Pre-finalization the only exit is governance `abort()` (admin-only, refunds treasury).
- Committee addresses are NEVER admin-supplied — only from the opt-in pool (VRF draw, or all opt-ins when pool ≤ 3). The old `PROJECT_COMMITTEE` role/param was deliberately removed. A stalled member can be replaced by an alternate via `promoteAlternate` — mirrors the release rule (admin+builder+≥1 member), clears the replaced slot's bits in the current milestone/cancellation bitmaps, and M is unchanged.
- `votingDeadline` is time-enforced (votes + `closeVoting`); the `urgent` bypass flag was deliberately removed — no admin voting bypasses.
- The award is bound to the votes: `awardProposal` reverts unless the proposal is in the top `numberOfShortlistedProjects` by vote count (`_requireInShortlist`, ties all pass), and only until `awardDeadline` (set at `closeVoting` = now + `deliberationWindow`). After it, anyone can `expireDeliberation` (nothing funded yet).
- A pending VRF draw cannot lock funds behind the admin: after `SELECTION_RETRY_DELAY` (7 days), anyone can `retryCommitteeSelection` or abort via `cancelProject`.
- One proposal per company per tender (`companyHasProposal`); companies must be `active` to bid.
- `mintInitialSupplyForProject` only mints into the calling governance's OWN escrow and at most its `budgetCap`; `committeeFeePerSignature` is capped at 1000 GES.

## EIP-712 escrow signatures (easy to get wrong)
- Signers sign typed digests; a relayer submits batches: `approveMilestone(Signature[])` / `approveCancellation(reasonHash, Signature[])` / `promoteAlternate(alternateIndex, memberIndex, Signature[])`. One tx can carry the whole committee.
- Relayer computes digests via `getMilestoneApprovalDigest(index, evidenceHash, signer)` / `getCancellationApprovalDigest(reasonHash, signer)` / `getAlternatePromotionDigest(alternateIndex, memberIndex, signer)`.
- Nonces are per-PURPOSE, NOT a single OZ Nonces counter: `milestoneNonces[signer][milestone]` (so pre-signed batches for different milestones never collide), `cancellationNonces[signer]`, `promotionNonces[signer]`. Each starts at 0 and increments on use — replay is still impossible.
- OZ `EIP712` handles the per-clone domain separator automatically (recompute path when `address(this) != cachedThis`) — do not add manual caching. `SignatureChecker` (EOA + ERC-1271) must stay — it's the account-abstraction future.

## Dependencies / remappings
- `@openzeppelin/contracts` → OZ 5.6.1 — the only OZ source for `src/`.
- `@openzeppelin/contracts@4.9.6` → pinned OZ 4.9.6 — needed ONLY by the Chainlink VRF mock (`EnumerableSet` import). Never import it from `src/`.
- `@chainlink/contracts` → `smartcontractkit/chainlink-evm` @ `contracts-v1.5.0` (chainlink-brownie-contracts is deprecated). New deps must be pinned submodules; check the imported OZ version in chainlink files before assuming.

## Testing quirks (test/ProjectEscrow.t.sol)
- Uses the official `VRFCoordinatorV2_5Mock`, deployed as `(0, 0, 1)` — `weiPerUnitLink` must be nonzero or LINK-payment fulfillment divides by zero.
- `vrf.addConsumer(subscriptionId, governanceAddr)` is required per project before award (the mock enforces consumer registration).
- Fulfill via `fulfillRandomWordsWithOverride(requestId, governance, words)`; `words.length` MUST equal the requested `numWords` (`min(pool, 5)`) or the mock reverts `InvalidRandomWords`.
- EIP-712 signing uses fixed private keys (`ADMIN_PK = 1`, `BUILDER_PK = 2`, members 100+) with `vm.sign` over digests from escrow getters; `memberAddrs`/`pkOf` fixtures live in `setUp`. Digests embed per-purpose nonces (`milestoneNonces[signer][index]` etc.), which start at 0 per purpose.
- Gotcha: helpers that make view calls (digest getters, `selectionRequestId()`) consume `vm.expectRevert` — compute values into locals BEFORE `expectRevert`.

## Deploy
- `script/Deploy.s.sol` holds the real Arbitrum Sepolia VRF v2.5 config (coordinator `0x5CE8D5A2BC84beb22a398CCA51996F7930313D61`, 50 gwei keyhash). `subscriptionId` is a TODO: create + fund at vrf.chain.link, and register each project's governance as a consumer (`registerConsumer` helper).
- Re-verify coordinator/keyhash against docs.chain.link/vrf/v2-5/supported-networks before any real deployment.