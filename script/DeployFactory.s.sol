// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {ProjectFactory} from "../src/ProjectFactory.sol";
import {IProjectConfig} from "../src/Interfaces/IProjectConfig.sol";

/// @notice Deploys ONLY a new ProjectFactory against the already-deployed
///         token/escrow/registry/VRF. Used to fix factory configuration
///         (role holder, duration minimums) without touching the other
///         contracts. Env: PRIVATE_KEY, CREATE_PROJECT_WALLET (role holder),
///         and optional MIN_PROPOSAL_SUBMISSION / MIN_VOTING (default 1 week).
///           MIN_PROPOSAL_SUBMISSION=60 MIN_VOTING=60 \
///           forge script script/DeployFactory.s.sol:DeployFactory \
///             --rpc-url $ARB_SEPOLIA_RPC --broadcast --verify
contract DeployFactory is Script {
    address public constant TOKEN = 0xDd29dfcFFBF40c4D3EEe68A880b62CdF4Bc828d5;
    address public constant ESCROW_IMPLEMENTATION = 0x9e59B978E8243d2c9E80703BECAabfe03bE715eB;
    address public constant REGISTRY = 0xC7c5D1A3F437f5Cfaa58Ad42d226B792042344Ff;
    address public constant VRF_COORDINATOR = 0x5CE8D5A2BC84beb22a398CCA51996F7930313D61;
    bytes32 public constant VRF_KEYHASH = 0x1770bdc7eec7771f7ba4ffd640f34260d7f095b79c92d34a5b2551d6f6cfd2be;

    function run() external returns (ProjectFactory factory) {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address createProjectWallet = vm.envAddress("CREATE_PROJECT_WALLET");
        uint64 minProposal = uint64(vm.envOr("MIN_PROPOSAL_SUBMISSION", uint256(1 weeks)));
        uint64 minVoting = uint64(vm.envOr("MIN_VOTING", uint256(1 weeks)));

        IProjectConfig.VRFConfig memory vrfConfig = IProjectConfig.VRFConfig({
            coordinator: VRF_COORDINATOR,
            subscriptionId: vm.envUint("VRF_SUBSCRIPTION_ID"),
            keyHash: VRF_KEYHASH,
            callbackGasLimit: 500_000,
            requestConfirmations: 3,
            nativePayment: false
        });

        vm.startBroadcast(deployerKey);
        factory = new ProjectFactory(
            minVoting, minProposal, minVoting, TOKEN, ESCROW_IMPLEMENTATION, createProjectWallet, REGISTRY, vrfConfig
        );
        vm.stopBroadcast();

        console.log("ProjectFactory:", address(factory));
        console.log("CREATE_PROJECT_ROLE holder:", createProjectWallet);
        console.log("minProposal:", minProposal, "minVoting:", minVoting);
    }
}
