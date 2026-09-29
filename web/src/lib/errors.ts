import { decodeAbiParameters, keccak256, toHex, type Address, type Hex } from "viem";
import { publicClient, governanceAt } from "./chain";

// Custom errors from the compiled artifacts. Selectors are computed at runtime,
// so this list stays in sync with src/ by construction.
const ERROR_SIGNATURES = [
  "AddressZero()",
  "AdminCannotOptIn()",
  "AlreadyOptedIn()",
  "AlreadySubmittedProposal()",
  "AwardDeadlinePassed()",
  "BudgetTooHigh()",
  "CompanyNotActive()",
  "EscrowNotCancelled()",
  "InsufficientRandomWords()",
  "InvalidHash()",
  "InvalidMilestoneCount()",
  "InvalidProjectLifecycle()",
  "InvalidRequestId()",
  "MilestoneReleased()",
  "MilestonesDontMatchCost()",
  "MilestonesNotAllReleased()",
  "NotInShortlist()",
  "InvalidShortlist()",
  "DuplicateShortlistEntry()",
  "NoProposalsToVoteOn()",
  "OptInClosed()",
  "ProposalDeadlinePassed()",
  "ProposalNonExistent()",
  "ProposalsDurationTooShort()",
  "SelectionNotPending()",
  "UnauthorisedCalled()",
  "UserAlreadyVoted()",
  "VotingClosed()",
  "VotingStillOpen()",
  "ZeroAmount()",
  "AccountingMismatch()",
  "AllMilestonesReleased()",
  "AlreadySigned()",
  "BuilderMustSubmitDirectly()",
  "BuilderMustSubmitFirst()",
  "CommitteeAlreadyFinalized()",
  "CommitteeNotFinalized()",
  "DuplicateSigner()",
  "InvalidAlternateIndex()",
  "InvalidMemberIndex()",
  "InvalidSignature()",
  "MilestoneAlreadyReleased()",
  "MilestonesDontMatchBudget()",
  "NoAlternates()",
  "NoMilestones()",
  "NotBuilder()",
  "NotSigner()",
  "ProjectCancelled()",
  "ProjectStillActive()",
  "ReasonMismatch()",
  "SettlementTooHigh()",
  "TooManyAlternates()",
  "TooManyMembers()",
  "ZeroBudget()",
  "FeeTooHigh()",
  "InvalidCategory()",
  "InvalidDeliberationWindow()",
  "InvalidDepartment()",
  "InvalidProposalSubmissionDuration()",
  "InvalidTitle()",
  "InvalidVRFConfig()",
  "InvalidVotingDuration()",
  "ProjectNonExistent()",
  "AlreadyRegistered()",
  "CompanyStateUnchanged()",
  "NotRegistered()",
] as const;

const SELECTOR_TO_NAME: Map<Hex, string> = new Map(
  ERROR_SIGNATURES.map((sig) => [keccak256(toHex(sig)).slice(0, 10) as Hex, sig.slice(0, -2)]),
);

const ERROR_STRING_SELECTOR = "0x08c379a0";

// viem buries the raw revert data three levels deep (CallExecutionError ->
// RpcRequestError -> raw RPC error). Drill down to get it.
export function extractRevertData(e: unknown): Hex | null {
  let cur: unknown = e;
  for (let i = 0; i < 4 && cur && typeof cur === "object"; i++) {
    const obj = cur as { data?: unknown; cause?: unknown };
    if (typeof obj.data === "string" && /^0x[0-9a-fA-F]+$/.test(obj.data)) return obj.data as Hex;
    cur = obj.cause;
  }
  const msg = e instanceof Error ? e.message : String(e);
  const hex = msg.match(/0x[0-9a-fA-F]{8,}/);
  return hex ? (hex[0] as Hex) : null;
}

// Decodes revert data into a readable reason: the custom error name for our
// contracts, or the revert string for Error(string).
export function decodeRevertReason(data: Hex): string | null {
  if (!data || data === "0x") return null;
  const selector = data.slice(0, 10) as Hex;
  if (selector === ERROR_STRING_SELECTOR) {
    try {
      return decodeAbiParameters([{ type: "string" }], `0x${data.slice(10)}`)[0];
    } catch {
      return null;
    }
  }
  return SELECTOR_TO_NAME.get(selector) ?? null;
}

export function formatDuration(seconds: bigint): string {
  const DAY = BigInt(86400);
  const HOUR = BigInt(3600);
  const MIN = BigInt(60);
  if (seconds <= BigInt(0)) return "0m";
  const days = seconds / DAY;
  const hours = (seconds % DAY) / HOUR;
  const minutes = (seconds % HOUR) / MIN;
  const parts: string[] = [];
  if (days > BigInt(0)) parts.push(`${days}d`);
  if (hours > BigInt(0)) parts.push(`${hours}h`);
  if (minutes > BigInt(0)) parts.push(`${minutes}m`);
  return parts.join(" ") || "less than a minute";
}

// Friendly, actionable messages for common lifecycle reverts. Time-based errors
// read the relevant deadline on-chain and report how much time remains.
export async function friendlyLifecycleError(e: unknown, governance: Address): Promise<string | null> {
  const reason = decodeRevertReason(extractRevertData(e) ?? "0x");
  if (!reason) return null;

  const g = governanceAt(governance);
const [proposalDeadline, votingDeadline] = await Promise.all([
    publicClient.readContract({ ...g, functionName: "proposalDeadline" }),
    publicClient.readContract({ ...g, functionName: "votingDeadline" }),
  ]);
  const now = (await publicClient.getBlock()).timestamp;

  switch (reason) {
    case "ProposalsDurationTooShort":
      return `Bidding hasn't closed yet — closes in ${formatDuration(proposalDeadline - now)}. You can open voting once the bidding window ends.`;
    case "VotingStillOpen":
      return `Voting hasn't closed yet — closes in ${formatDuration(votingDeadline - now)}. You can close voting and fix the shortlist after that.`;
    case "AwardDeadlinePassed":
      return "The award window has passed — you can no longer award. Expire the tender to close it without funding.";
    case "NoProposalsToVoteOn":
      return "No bids were submitted for this tender, so voting can't open. The tender stays in bidding until it's dealt with.";
    case "NotInShortlist":
      return "That proposal isn't in the vote-bound shortlist — only shortlisted proposals can be awarded.";
    case "ProposalDeadlinePassed":
      return "Bidding has closed — no new bids can be submitted.";
    case "VotingClosed":
      return "Voting has closed — no more votes can be cast.";
    case "OptInClosed":
      return "The opt-in window has closed for this tender.";
    case "InvalidProjectLifecycle":
      return "This action isn't valid in the tender's current stage.";
    case "SelectionNotPending":
      return "There is no pending committee draw to retry.";
    case "EscrowNotCancelled":
      return "The escrow hasn't been cancelled yet.";
    case "MilestonesNotAllReleased":
      return "Not all milestones are released yet — the project can't be completed.";
    case "UnauthorisedCalled":
      return "Only the committee can perform this action.";
    case "AlreadySubmittedProposal":
      return "Your company already has a bid on this tender — one bid per company.";
    case "CompanyNotActive":
      return "Your company is deregistered — reactivate it before bidding.";
    case "BudgetTooHigh":
      return "Your bid exceeds the tender's budget cap.";
    case "MilestonesDontMatchCost":
      return "Your milestone amounts must add up to your bid cost.";
    case "ZeroAmount":
      return "Amounts must be greater than zero.";
    case "UserAlreadyVoted":
      return "You've already voted on this tender.";
    case "AlreadyOptedIn":
      return "You're already opted in to the committee pool.";
    case "AdminCannotOptIn":
      return "The committee admin can't opt in — opt-in is for members.";
    case "MilestoneReleased":
      return "This milestone is already released.";
    case "BuilderMustSubmitFirst":
      return "The builder must submit completion evidence before anyone can approve.";
    case "CommitteeNotFinalized":
      return "The committee hasn't been drawn yet — this is locked until then.";
    case "NotSigner":
      return "Only committee members can sign this.";
    case "AlreadySigned":
      return "You've already signed this.";
    default:
      return null;
  }
}

export async function friendlyError(e: unknown): Promise<string | null> {
  const reason = decodeRevertReason(extractRevertData(e) ?? "0x");
  if (!reason) return null;
  switch (reason) {
    case "ZeroBudget":
      return "The tender budget must be greater than zero.";
    case "InvalidMilestoneCount":
      return "Milestones are required — at least one.";
    case "FeeTooHigh":
      return "The committee fee is above the platform cap.";
    case "AlreadyRegistered":
      return "Your company is already registered.";
    case "NotRegistered":
      return "Your company isn't registered yet.";
    case "CompanyStateUnchanged":
      return "No change to save — the company is already in that state.";
    case "AddressZero":
      return "A wallet address can't be zero.";
    case "InvalidHash":
      return "A content hash is required — upload the document.";
    case "ZeroAmount":
      return "Amounts must be greater than zero.";
    case "InvalidDestination":
      return "A destination reference is required.";
    case "NotPending":
      return "That receipt has already been paid or rejected.";
    case "ProjectNonExistent":
      return "That proposal doesn't exist.";
    case "ProposalNonExistent":
      return "That proposal doesn't exist.";
    case "AlreadySubmittedProposal":
      return "Your company already has a bid on this tender — one bid per company.";
    case "CompanyNotActive":
      return "Your company is deregistered — reactivate it before bidding.";
    case "BudgetTooHigh":
      return "Your bid exceeds the tender's budget cap.";
    case "MilestonesDontMatchCost":
      return "Your milestone amounts must add up to your bid cost.";
    case "MilestonesDontMatchBudget":
      return "Your milestone amounts must add up to your bid cost.";
    case "UserAlreadyVoted":
      return "You've already voted on this tender.";
    case "AlreadyOptedIn":
      return "You're already opted in to the committee pool.";
    case "AdminCannotOptIn":
      return "The committee admin can't opt in — opt-in is for members.";
    case "MilestoneReleased":
      return "This milestone is already released.";
    case "MilestoneAlreadyReleased":
      return "This milestone is already released.";
    case "BuilderMustSubmitFirst":
      return "The builder must submit completion evidence before anyone can approve.";
    case "BuilderMustSubmitDirectly":
      return "The builder must submit completion evidence directly.";
    case "CommitteeNotFinalized":
      return "The committee hasn't been drawn yet — this is locked until then.";
    case "NotSigner":
      return "Only committee members can sign this.";
    case "AlreadySigned":
      return "You've already signed this.";
    case "NotBuilder":
      return "Only the awarded builder can submit completion evidence.";
    case "ProjectCancelled":
      return "This project has been cancelled.";
    case "ProjectStillActive":
      return "This project is still active.";
    case "AllMilestonesReleased":
      return "All milestones have already been released.";
    case "NoMilestones":
      return "No milestones exist on this escrow.";
    case "InvalidSignature":
      return "One of the signatures is invalid.";
    case "ReasonMismatch":
      return "All cancellation signatures must commit to the same reason.";
    case "InvalidMemberIndex":
      return "That committee member doesn't exist.";
    case "InvalidAlternateIndex":
      return "That alternate doesn't exist.";
    case "NoAlternates":
      return "There are no alternates on this committee.";
    case "TooManyMembers":
      return "Too many committee members.";
    case "TooManyAlternates":
      return "Too many alternates.";
    case "DuplicateSigner":
      return "The same wallet can't sign twice.";
    case "SettlementTooHigh":
      return "That settlement exceeds what the escrow can pay.";
    case "AccountingMismatch":
      return "The escrow accounting check failed.";
    case "InvalidRequestId":
      return "The VRF response didn't match the pending draw.";
    case "InsufficientRandomWords":
      return "The randomness response had too few words.";
    case "SelectionNotPending":
      return "There is no pending committee draw to retry.";
    case "NotInShortlist":
      return "That proposal isn't in the vote-bound shortlist — only shortlisted proposals can be awarded.";
    case "InvalidShortlist":
      return "The shortlist must be exactly the top proposals by votes, ties all pass.";
    case "DuplicateShortlistEntry":
      return "The shortlist contains a duplicate proposal.";
    case "NoProposalsToVoteOn":
      return "No bids were submitted for this tender, so voting can't open. The tender stays in bidding until it's dealt with.";
    case "AwardDeadlinePassed":
      return "The award window has passed — you can no longer award. Expire the tender to close it without funding.";
    case "ProposalDeadlinePassed":
      return "Bidding has closed — no new bids can be submitted.";
    case "VotingClosed":
      return "Voting has closed — no more votes can be cast.";
    case "OptInClosed":
      return "The opt-in window has closed for this tender.";
    case "InvalidProjectLifecycle":
      return "This action isn't valid in the tender's current stage.";
    case "UnauthorisedCalled":
      return "Only the committee can perform this action.";
    case "EscrowNotCancelled":
      return "The escrow hasn't been cancelled yet.";
    case "MilestonesNotAllReleased":
      return "Not all milestones are released yet — the project can't be completed.";
    case "InvalidMilestoneCount":
      return "Milestones are required — at least one.";
    case "ZeroAmount":
      return "Amounts must be greater than zero.";
    case "AddressZero":
      return "A wallet address can't be zero.";
    case "InvalidHash":
      return "A content hash is required — upload the document.";
    case "InvalidDestination":
      return "A destination reference is required.";
    case "NotPending":
      return "That receipt has already been paid or rejected.";
    default:
      return null;
  }
}