// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title Redemption
/// @notice The off-ramp: converts Payment Token back into real-world money.
///
///         Flow: a holder burns GES and receives a transferable ERC-721
///         receipt NFT as on-chain proof of the burn (amount, originating
///         escrow/project, KYC'd destination reference). The paying authority
///         verifies the receipt on-chain, pays the real-world destination in
///         fiat, then flips the receipt to `paid` (with a payout reference)
///         via markPaid - or `rejected` if the request cannot be honoured.
///
///         The receipt is the terminal artifact of a token's lifecycle: it
///         permanently links the burn to the project and the payout, so the
///         full chain (mint -> escrow -> milestone -> burn -> fiat) is
///         auditable. It is transferable (state follows the tokenId, not the
///         owner) and is intended to become the primitive of the builder
///         track record.
/// @dev The contract holds the token's FACTORY role so it is the ONLY burner
///      of supply (peg integrity: every burned unit was minted against real
///      money that the paying authority honours on proof of burn).
contract Redemption is ERC721, AccessControl {
    using SafeERC20 for IERC20;

    enum ReceiptState {
        Pending,
        Paid,
        Rejected
    }

    struct Receipt {
        address redeemer; // Who burned the tokens.
        address escrow; // The escrow/project that paid the redeemer (recorded, not enforced - tokens are fungible).
        uint256 amount; // GES burned, raw units (18 decimals).
        bytes32 destinationId; // Hash of the KYC'd payout destination; full details stay off-chain.
        ReceiptState state;
        string payoutRef; // Paying authority's payment reference, set on markPaid.
    }

    bytes32 public constant PAYER_ROLE = keccak256("PAYER_ROLE");

    IERC20 public immutable PAYMENT_TOKEN;
    uint256 public receiptCount;

    mapping(uint256 tokenId => Receipt receipt) public receipts;

    // --------------------------------------------------------------------------
    // -----------------------------------> ERRORS / EVENTS <---------------------
    // --------------------------------------------------------------------------

    error ZeroAmount();
    error AddressZero();
    error InvalidDestination();
    error NotPending();

    event ReceiptIssued(
        uint256 indexed tokenId, address indexed redeemer, address escrow, uint256 amount, bytes32 destinationId
    );
    event ReceiptPaid(uint256 indexed tokenId, string payoutRef);
    event ReceiptRejected(uint256 indexed tokenId, bytes32 reason);

    /// @notice Deploys the off-ramp.
    /// @param _paymentToken The token that can be redeemed.
    /// @param _payer The paying authority (bank bridge / payment processor
    ///        keeper); receives PAYER_ROLE and is the only address that can
    ///        mark receipts paid or rejected.
    /// @dev The deployer receives DEFAULT_ADMIN_ROLE (may grant more payers).
    constructor(address _paymentToken, address _payer) ERC721("DemocraFund Redemption Receipt", "DFR") {
        if (_paymentToken == address(0)) revert AddressZero();
        if (_payer == address(0)) revert AddressZero();

        PAYMENT_TOKEN = IERC20(_paymentToken);

        _grantRole(PAYER_ROLE, _payer);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    // --------------------------------------------------------------------------
    // ---------------------------------------> REDEMPTION <---------------------
    // --------------------------------------------------------------------------

    /// @notice Burns the caller's tokens and mints a receipt NFT.
    /// @param _amount GES to redeem (raw units), pulled from the caller via
    ///        ERC-20 allowance to this contract.
    /// @param _destinationId Hash of the KYC'd payout destination (bank
    ///        account reference). Full details live off-chain.
    /// @param _escrow The escrow/project the tokens were earned from - burned
    ///        into the receipt as provenance.
    /// @return tokenId The receipt NFT id.
    /// @dev Permissionless: anyone holding GES can off-ramp. The payment
    ///      token is pulled in and burned in the same transaction, so the
    ///      redeemed supply is destroyed before any fiat can be claimed.
    function redeem(uint256 _amount, bytes32 _destinationId, address _escrow) external returns (uint256 tokenId) {
        if (_amount == 0) revert ZeroAmount();
        if (_destinationId == bytes32(0)) revert InvalidDestination();
        if (_escrow == address(0)) revert AddressZero();

        tokenId = ++receiptCount;
        receipts[tokenId] = Receipt({
            redeemer: msg.sender,
            escrow: _escrow,
            amount: _amount,
            destinationId: _destinationId,
            state: ReceiptState.Pending,
            payoutRef: ""
        });

        PAYMENT_TOKEN.safeTransferFrom(msg.sender, address(this), _amount);
        IPaymentTokenLike(address(PAYMENT_TOKEN)).burn(address(this), _amount);

        _mint(msg.sender, tokenId);

        emit ReceiptIssued(tokenId, msg.sender, _escrow, _amount, _destinationId);
    }

    /// @notice Confirms a fiat payout was made for a receipt.
    /// @param _tokenId The receipt NFT id.
    /// @param _payoutRef The paying authority's own payment reference.
    /// @dev PAYER_ROLE only; the on-chain proof that the burn was honoured.
    function markPaid(uint256 _tokenId, string calldata _payoutRef) external onlyRole(PAYER_ROLE) {
        Receipt storage receipt = receipts[_tokenId];
        if (receipt.state != ReceiptState.Pending) revert NotPending();

        receipt.state = ReceiptState.Paid;
        receipt.payoutRef = _payoutRef;

        emit ReceiptPaid(_tokenId, _payoutRef);
    }

    /// @notice Marks a redemption request as rejected (e.g. mismatch with the
    ///         KYC'd destination).
    /// @param _tokenId The receipt NFT id.
    /// @param _reason A public justification.
    /// @dev PAYER_ROLE only. A rejected receipt cannot be paid later; the
    ///      redeemer may start a new redemption for another destination.
    function markRejected(uint256 _tokenId, bytes32 _reason) external onlyRole(PAYER_ROLE) {
        Receipt storage receipt = receipts[_tokenId];
        if (receipt.state != ReceiptState.Pending) revert NotPending();
        if (_reason == bytes32(0)) revert InvalidDestination();

        receipt.state = ReceiptState.Rejected;

        emit ReceiptRejected(_tokenId, _reason);
    }

    // --------------------------------------------------------------------------
    // ------------------------------------------> METADATA <--------------------
    // --------------------------------------------------------------------------

    /// @notice On-chain JSON metadata for a receipt (data URI): who redeemed,
    ///         from which project, how much, and the current state.
    /// forge-lint: disable-next-line(mixed-case-function) // ERC-721 interface requires the exact name.
    function tokenURI(uint256 _tokenId) public view override returns (string memory) {
        Receipt memory r = receipts[_tokenId];
        string memory stateName =
            r.state == ReceiptState.Paid ? "paid" : r.state == ReceiptState.Rejected ? "rejected" : "pending";

        return string.concat(
            "data:application/json,",
            '{"name":"DemocraFund Redemption Receipt #',
            _toString(_tokenId),
            '","redeemer":"',
            _toString(uint256(uint160(r.redeemer))),
            '","escrow":"',
            _toString(uint256(uint160(r.escrow))),
            '","amount":',
            _toString(r.amount),
            ',"state":"',
            stateName,
            '"}'
        );
    }

    /// @dev Minimal uint256 -> decimal string helper for the metadata URI.
    function _toString(uint256 _value) internal pure returns (string memory) {
        if (_value == 0) return "0";
        uint256 digits;
        uint256 tmp = _value;
        while (tmp != 0) {
            tmp /= 10;
            digits++;
        }
        bytes memory out = new bytes(digits);
        while (_value != 0) {
            digits--;
            out[digits] = bytes1(uint8(48 + (_value % 10)));
            _value /= 10;
        }
        return string(out);
    }

    /// @dev Both bases define supportsInterface; merge them so the receipt is
    ///      both a valid ERC-721 and a valid access-controlled contract.
    function supportsInterface(bytes4 interfaceId) public view override(ERC721, AccessControl) returns (bool) {
        return ERC721.supportsInterface(interfaceId) || AccessControl.supportsInterface(interfaceId);
    }
}

/// @notice Minimal burn surface of the payment token (avoids importing the
///         full token contract into Redemption).
interface IPaymentTokenLike {
    function burn(address _from, uint256 _amount) external;
}
