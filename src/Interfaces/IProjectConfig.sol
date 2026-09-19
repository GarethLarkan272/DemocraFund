// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @notice Shared configuration structs used by ProjectFactory and
///         ProjectGovernance when a project is created.
interface IProjectConfig {
    /// @notice Everything a tender needs to be created.
    /// @dev Field order is optimised for storage packing when held in a
    ///      struct: 32-byte values first, then the two 8-byte deadlines,
    ///      then the two 20-byte addresses.
    struct ProjectConfig {
        uint256 budgetCap;
        /// @notice Tokens minted to each committee member per milestone they
        ///         sign. Zero disables committee compensation; capped at
        ///         MAX_COMMITTEE_FEE_PER_SIGNATURE by the factory.
        uint256 committeeFeePerSignature;
        bytes32 title;
        bytes32 category;
        bytes32 department;
        bytes32 specContentHash;
        bytes32 ipfsHash;
        uint64 proposalDeadline;
        uint64 votingDeadline;
        /// @notice How long the admin has to award after voting closes. Once
        ///         it passes, anyone can expire the project (no funds at
        ///         stake yet) - the award decision cannot stall forever.
        uint64 deliberationWindow;
        address governanceSafeWallet;
        address treasuryWallet;
    }

    /// @notice Chainlink VRF v2.5 subscription + gas lane configuration.
    /// @dev The 20-byte coordinator shares a slot with the 4/2/1-byte params
    ///      (27 bytes used) instead of wasting a full slot of its own.
    /// forge-lint: disable-next-line(pascal-case-struct) // Acronym-first name, referenced everywhere as IProjectConfig.VRFConfig.
    struct VRFConfig {
        uint256 subscriptionId;
        bytes32 keyHash;
        address coordinator;
        uint32 callbackGasLimit;
        uint16 requestConfirmations;
        bool nativePayment;
    }
}
