import { createPublicClient, createWalletClient, http, type Address } from "viem";
import { arbitrumSepolia } from "viem/chains";
import { DEPLOYED, RPC_URL } from "./config";
import {
  PaymentTokenAbi,
  CompanyRegistryAbi,
  ProjectFactoryAbi,
  ProjectGovernanceAbi,
  ProjectEscrowAbi,
  RedemptionAbi,
} from "./abi";

export const publicClient = createPublicClient({
  chain: arbitrumSepolia,
  transport: http(RPC_URL),
});

export const paymentToken = {
  address: DEPLOYED.PaymentToken as Address,
  abi: PaymentTokenAbi,
};

export const companyRegistry = {
  address: DEPLOYED.CompanyRegistry as Address,
  abi: CompanyRegistryAbi,
};

export const projectFactory = {
  address: DEPLOYED.ProjectFactory as Address,
  abi: ProjectFactoryAbi,
};

export const redemption = {
  address: DEPLOYED.Redemption as Address,
  abi: RedemptionAbi,
};

export const governanceAt = (address: Address) =>
  ({ address, abi: ProjectGovernanceAbi }) as const;

export const escrowAt = (address: Address) =>
  ({ address, abi: ProjectEscrowAbi }) as const;