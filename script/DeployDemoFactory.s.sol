// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {ProjectFactory} from "../src/ProjectFactory.sol";
import {PaymentToken} from "../src/PaymentToken.sol";
import {IProjectConfig} from "../src/Interfaces/IProjectConfig.sol";

/// @notice Demo-flavoured factory redeploy: same stack, but with 5-minute
///         phase minimums instead of 1 week so the live demo can run in one
///         sitting. The rest of the deployed stack is reused as-is.
contract DeployDemoFactory is Script {
    address public constant TOKEN = 0x249f87153FD7E6e8679A094f1C9ACf4B8Cac9A18;
    address public constant ESCROW_IMPL = 0x91Fb401De682b87767C7F2F47ea44b704b669043;
    address public constant REGISTRY = 0x477f174b5eCeBbB0F3178E523c9274703C632e85;
    address public constant COMMITTEE_WALLET = 0x3b7C8c79EBb5BaF1195a381A34319b8e1A5Ab462; // derived custodial committee wallet
    address public constant COORDINATOR = 0x5CE8D5A2BC84beb22a398CCA51996F7930313D61;
    bytes32 public constant KEYHASH = 0x1770bdc7eec7771f7ba4ffd640f34260d7f095b79c92d34a5b2551d6f6cfd2be;
    uint256 public constant SUB_ID = 35152182209447658705524417127598446980824408461048413491098011822516358913899;
    uint32 public constant CALLBACK_GAS = 300_000;
    uint16 public constant CONFIRMATIONS = 3;

    uint64 public constant DEMO_MIN = 1 minutes;

    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerKey);

        IProjectConfig.VRFConfig memory vrf = IProjectConfig.VRFConfig({
            coordinator: COORDINATOR,
            subscriptionId: SUB_ID,
            keyHash: KEYHASH,
            callbackGasLimit: CALLBACK_GAS,
            requestConfirmations: CONFIRMATIONS,
            nativePayment: false
        });

        ProjectFactory factory =
            new ProjectFactory(DEMO_MIN, DEMO_MIN, DEMO_MIN, TOKEN, ESCROW_IMPL, COMMITTEE_WALLET, REGISTRY, vrf);
        PaymentToken(TOKEN).setFactoryRole(address(factory));
        vm.stopBroadcast();

        console.log("ProjectFactory (demo):", address(factory));
    }
}
