const addr = (v: string | undefined, fallback: string) => (v?.trim() ? v.trim() : fallback);

export const DEPLOYED = {
  chainId: Number(process.env.CHAIN_ID ?? "421614"),
  PaymentToken: addr(process.env.DEPLOYED_PAYMENT_TOKEN, "0x249f87153FD7E6e8679A094f1C9ACf4B8Cac9A18") as `0x${string}`,
  ProjectEscrowImplementation: addr(
    process.env.DEPLOYED_PROJECT_ESCROW_IMPLEMENTATION,
    "0x91Fb401De682b87767C7F2F47ea44b704b669043",
  ) as `0x${string}`,
  CompanyRegistry: addr(process.env.DEPLOYED_COMPANY_REGISTRY, "0x477f174b5eCeBbB0F3178E523c9274703C632e85") as `0x${string}`,
  Redemption: addr(process.env.DEPLOYED_REDEMPTION, "0x9c2EeAEbe67836e3293a7b29206bB824971f5758") as `0x${string}`,
  ProjectFactory: addr(process.env.DEPLOYED_PROJECT_FACTORY, "0x3EDDFb002Bf1c7d1ECB0E2307c30d92dA1BF1F59") as `0x${string}`,
} as const;

export const VRF_SUBSCRIPTION_ID = process.env.VRF_SUBSCRIPTION_ID ?? "0";

export const RPC_URL =
  process.env.ARB_SEPOLIA_RPC ?? "https://sepolia-rollup.arbitrum.io/rpc";

// Gas threshold for custodial wallets: below this the relayer tops up from the sponsor.
export const MIN_WALLET_BALANCE = BigInt("2000000000000000"); // 0.002 ETH
export const TOPUP_AMOUNT = BigInt("5000000000000000"); // 0.005 ETH

// GES is an 18-decimal ERC-20. Human amounts are multiplied on the way into
// the contracts and divided on the way out.
export const GES_DECIMALS = 18;
export const TOKEN_SYMBOL = "HZAR"; // display symbol - change when the token is renamed
export const TOKEN_NAME = "Humewood ZAR"; // the on-chain ERC-20 name
export const TO_WEI = (human: string | number) => {
  const [int, frac = ""] = String(human).split(".");
  const padded = (frac + "0".repeat(18)).slice(0, 18);
  return BigInt(int) * BigInt(10) ** BigInt(18) + BigInt(padded || "0");
};
export const weiToGES = (wei: string | number | bigint) => (Number(wei) / 10 ** 18).toString();