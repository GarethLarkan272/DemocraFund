// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {ProjectFactory} from "../src/ProjectFactory.sol";
import {ProjectEscrow} from "../src/ProjectEscrow.sol";
import {PaymentToken} from "../src/PaymentToken.sol";
import {CompanyRegistry} from "../src/CompanyRegistry.sol";
import {Redemption} from "../src/Redemption.sol";
import {IProjectConfig} from "../src/Interfaces/IProjectConfig.sol";
import {IVRFSubscriptionV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/interfaces/IVRFSubscriptionV2Plus.sol";

/// @notice Deploys the DemocraFund core against Chainlink VRF v2.5.
///
///         Usage (Arbitrum Sepolia):
///           forge script script/Deploy.s.sol:Deploy --rpc-url $ARB_SEPOLIA_RPC --broadcast
///
///         Before the demo, in the VRF Subscription Manager (vrf.chain.link):
///           1. Create a subscription, fund it with LINK (faucets.chain.link).
///           2. Add each deployed project's governance contract as a consumer
///              (the factory emits ProjectCreated with the address, and
///              registerConsumer below does it on-chain).
contract Deploy is Script {
    // ---- Chainlink VRF v2.5 - Arbitrum Sepolia (verify at docs.chain.link/vrf/v2-5/supported-networks) ----
    address public constant ARBITRUM_SEPOLIA_VRF_COORDINATOR = 0x5CE8D5A2BC84beb22a398CCA51996F7930313D61;
    bytes32 public constant ARBITRUM_SEPOLIA_KEYHASH_50_GWEI =
        0x1770bdc7eec7771f7ba4ffd640f34260d7f095b79c92d34a5b2551d6f6cfd2be;
    uint16 public constant REQUEST_CONFIRMATIONS = 3;
    uint32 public constant CALLBACK_GAS_LIMIT = 300_000;

    uint64 public constant MIN_PROPOSAL_SUBMISSION = 1 weeks;
    uint64 public constant MIN_VOTING = 1 weeks;
    uint256 public constant GLOBAL_MIN_VOTING = 1 weeks;

    function run()
        external
        returns (ProjectFactory factory, PaymentToken token, CompanyRegistry registry, Redemption redemption)
    {
        // Create (or reuse) the subscription at vrf.chain.link and put the ID here.
        uint256 subscriptionId = 0; // TODO: fill in from vrf.chain.link

        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);
        address createProjectWallet = vm.envAddress("CREATE_PROJECT_WALLET"); // role that can create projects
        address payerWallet = vm.envAddress("PAYER_WALLET"); // the paying authority that honours redemptions
        vm.startBroadcast(deployerKey);

        token = new PaymentToken(deployer);
        ProjectEscrow escrowImpl = new ProjectEscrow();
        registry = new CompanyRegistry();
        redemption = new Redemption(address(token), payerWallet);

        IProjectConfig.VRFConfig memory vrfConfig = IProjectConfig.VRFConfig({
            coordinator: ARBITRUM_SEPOLIA_VRF_COORDINATOR,
            subscriptionId: subscriptionId,
            keyHash: ARBITRUM_SEPOLIA_KEYHASH_50_GWEI,
            callbackGasLimit: CALLBACK_GAS_LIMIT,
            requestConfirmations: REQUEST_CONFIRMATIONS,
            nativePayment: false
        });

        factory = new ProjectFactory(
            GLOBAL_MIN_VOTING,
            MIN_PROPOSAL_SUBMISSION,
            MIN_VOTING,
            address(token),
            address(escrowImpl),
            createProjectWallet,
            address(registry),
            vrfConfig
        );
        token.setFactoryRole(address(factory));
        token.setFactoryRole(address(redemption)); // the sole burner: proof-of-burn off-ramp

        vm.stopBroadcast();

        console.log("PaymentToken:", address(token));
        console.log("ProjectEscrow implementation:", address(escrowImpl));
        console.log("CompanyRegistry:", address(registry));
        console.log("Redemption (off-ramp + receipts):", address(redemption));
        console.log("ProjectFactory:", address(factory));
        console.log("VRF subscriptionId:", subscriptionId);
    }

    /// @notice Adds a deployed project's governance contract as a consumer of
    ///         the shared VRF subscription (must be called by the subscription
    ///         owner). The factory emits ProjectCreated with the address.
    function registerConsumer(uint256 _subscriptionId, address _governance) external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerKey);
        IVRFSubscriptionV2Plus(ARBITRUM_SEPOLIA_VRF_COORDINATOR).addConsumer(_subscriptionId, _governance);
        vm.stopBroadcast();
    }
}
