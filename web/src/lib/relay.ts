import { createWalletClient, http, type Address, type Hash, type Hex } from "viem";
import { arbitrumSepolia } from "viem/chains";
import { privateKeyToAccount, type Account } from "viem/accounts";
import { publicClient } from "./chain";
import { MIN_WALLET_BALANCE, RPC_URL, TOPUP_AMOUNT } from "./config";

// The sponsor wallet pays gas for every custodial user. Funded once with
// testnet ETH; it tops up derived wallets as they spend down.
export const sponsorAccount = privateKeyToAccount(process.env.SPONSOR_PK as Address);

export type TxRequest = { to: Address; data: Hex; value?: bigint };

async function ensureGas(account: Account) {
  const balance = await publicClient.getBalance({ address: account.address });
  if (balance < MIN_WALLET_BALANCE) {
    const sponsorClient = createWalletClient({
      account: sponsorAccount,
      chain: arbitrumSepolia,
      transport: http(RPC_URL),
    });
    await sponsorClient.sendTransaction({ to: account.address, value: TOPUP_AMOUNT });
  }
}

// Signs and submits a transaction as the given custodial account, topping up
// gas first if needed. Returns the receipt - throws on revert.
export async function submit(
  account: Account,
  tx: TxRequest,
  label?: string,
): Promise<{ hash: Hash; status: boolean }> {
  await ensureGas(account);
  const client = createWalletClient({
    account,
    chain: arbitrumSepolia,
    transport: http(RPC_URL),
  });
  const hash = await client.sendTransaction(tx);
  const receipt = await publicClient.waitForTransactionReceipt({ hash });
  if (receipt.status !== "success") {
    throw new Error(`Transaction reverted: ${label ?? tx.data.slice(0, 10)}`);
  }
  return { hash: receipt.transactionHash, status: true };
}