import { type Hex, type Address } from "viem";
import type { PrivateKeyAccount } from "viem/accounts";
import { publicClient, escrowAt } from "./chain";

// EIP-712 escrow signatures, exactly as the contracts expect:
//   - digest = the escrow's typed-data digest (embeds the signer's per-purpose nonce)
//   - signature = raw 32-byte hash signing (like vm.sign), packed as abi.encodePacked(r, s, v)
export type EscrowSig = { signer: Address; signature: Hex };

// The account's own sign() knows its private key (viem's privateKeyToAccount
// does NOT expose the key via .source - that field is the string "privateKey").
// It returns a packed 65-byte hex (r||s||v) which is exactly what the escrow's
// abi.encodePacked(r, s, v) expects, so no repacking is needed.
export async function escrowSignature(
  account: PrivateKeyAccount,
  escrow: Address,
  digest: Hex,
): Promise<EscrowSig> {
  const packed = await account.sign({ hash: digest });
  return {
    signer: account.address,
    signature: packed,
  };
}

export async function milestoneSigs(
  account: PrivateKeyAccount,
  escrow: Address,
  milestoneIndex: number,
  evidenceHash: Hex,
): Promise<EscrowSig> {
  const digest = await publicClient.readContract({
    ...escrowAt(escrow),
    functionName: "getMilestoneApprovalDigest",
    args: [BigInt(milestoneIndex), evidenceHash, account.address],
  });
  return escrowSignature(account, escrow, digest);
}

export async function cancellationSigs(
  account: PrivateKeyAccount,
  escrow: Address,
  reasonHash: Hex,
): Promise<EscrowSig> {
  const digest = await publicClient.readContract({
    ...escrowAt(escrow),
    functionName: "getCancellationApprovalDigest",
    args: [reasonHash, account.address],
  });
  return escrowSignature(account, escrow, digest);
}