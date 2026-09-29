// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @title CompanyRegistry
/// @notice Permissionless registry of companies that may bid on tenders.
///         Each company stores only the minimum needed on-chain:
///           - companyId: sequential, assigned on registration,
///           - adminWallet: the company's on-chain identity; only this wallet
///             can submit proposals and update the company's details. It also
///             receives milestone payouts - there is no separate payment
///             wallet, because builders off-ramp via redemption, so money
///             simply lands in the identity wallet.
///           - infoHash: hash of the company's full off-chain information
///             (registration documents, tax ids, certifications).
/// @dev One admin wallet == one company (companyIdOfAdmin). There is no
///      deletion: a company is registered once and its wallets/hash evolve via
///      updateCompany. ProjectGovernance reads this registry in
///      createProposal, so bids reference companyId instead of wallets.
contract CompanyRegistry {
    struct Company {
        address adminWallet; // 20 bytes.
        bytes32 infoHash; // 32 bytes.
        bool active; // 1 byte; false = deregistered, cannot bid.
    }

    uint256 public companyCount;
    mapping(uint256 companyId => Company company) public companies;
    mapping(address adminWallet => uint256 companyId) public companyIdOfAdmin;

    // --------------------------------------------------------------------------
    // -----------------------------------> ERRORS / EVENTS <---------------------
    // --------------------------------------------------------------------------

    error AlreadyRegistered();
    error NotRegistered();
    error CompanyNotActive();
    error CompanyStateUnchanged();
    error InvalidHash();

    event CompanyRegistered(uint256 indexed companyId, address indexed adminWallet, bytes32 infoHash);
    event CompanyUpdated(uint256 indexed companyId, bytes32 infoHash);
    event CompanyActivated(uint256 indexed companyId, bool active);

    // --------------------------------------------------------------------------
    // -------------------------------------> COMPANY LIFECYCLE <-----------------
    // --------------------------------------------------------------------------

    /// @notice Registers the caller as a company.
    /// @param _infoHash Hash of the company's off-chain information.
    /// @return companyId The assigned sequential ID (starts at 1).
    /// @dev Self-registration: the caller becomes the adminWallet, which is
    ///      also the payout wallet for milestone releases. Any wallet can
    ///      register, but a wallet can only ever control one company.
    function registerCompany(bytes32 _infoHash) external returns (uint256 companyId) {
        if (companyIdOfAdmin[msg.sender] != 0) revert AlreadyRegistered();
        if (_infoHash == bytes32(0)) revert InvalidHash();

        companyId = ++companyCount;
        companies[companyId] = Company({adminWallet: msg.sender, infoHash: _infoHash, active: true});
        companyIdOfAdmin[msg.sender] = companyId;

        emit CompanyRegistered(companyId, msg.sender, _infoHash);
    }

    /// @notice Updates the company's information hash.
    /// @param _infoHash The new information hash.
    /// @dev adminWallet only. Changes affect future proposals and awards
    ///      only - proposals already submitted keep the wallets they used.
    function updateCompany(bytes32 _infoHash) external {
        uint256 companyId = companyIdOfAdmin[msg.sender];
        if (companyId == 0) revert NotRegistered();
        if (_infoHash == bytes32(0)) revert InvalidHash();

        Company storage company = companies[companyId];
        company.infoHash = _infoHash;

        emit CompanyUpdated(companyId, _infoHash);
    }

    /// @notice Toggles whether the company may bid on tenders.
    /// @param _active false = deregister (cannot submit proposals, existing
    ///        proposals are unaffected); true = re-register.
    /// @dev adminWallet only. Changes are immediate for future proposals.
    function setCompanyActive(bool _active) external {
        uint256 companyId = companyIdOfAdmin[msg.sender];
        if (companyId == 0) revert NotRegistered();
        if (companies[companyId].active == _active) revert CompanyStateUnchanged();

        companies[companyId].active = _active;

        emit CompanyActivated(companyId, _active);
    }
}
