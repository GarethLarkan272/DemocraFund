export const ProjectEscrowAbi = [
  {
    "type": "constructor",
    "inputs": [],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "ADMIN_SLOT",
    "inputs": [],
    "outputs": [
      {
        "name": "",
        "type": "uint8",
        "internalType": "uint8"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "ALTERNATE_PROMOTION_TYPEHASH",
    "inputs": [],
    "outputs": [
      {
        "name": "",
        "type": "bytes32",
        "internalType": "bytes32"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "CANCELLATION_APPROVAL_TYPEHASH",
    "inputs": [],
    "outputs": [
      {
        "name": "",
        "type": "bytes32",
        "internalType": "bytes32"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "MAX_MEMBERS",
    "inputs": [],
    "outputs": [
      {
        "name": "",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "MAX_MILESTONES",
    "inputs": [],
    "outputs": [
      {
        "name": "",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "MILESTONE_APPROVAL_TYPEHASH",
    "inputs": [],
    "outputs": [
      {
        "name": "",
        "type": "bytes32",
        "internalType": "bytes32"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "abort",
    "inputs": [],
    "outputs": [],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "adminSigner",
    "inputs": [],
    "outputs": [
      {
        "name": "",
        "type": "address",
        "internalType": "address"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "allMilestonesReleased",
    "inputs": [],
    "outputs": [
      {
        "name": "",
        "type": "bool",
        "internalType": "bool"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "alternates",
    "inputs": [
      {
        "name": "",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "outputs": [
      {
        "name": "",
        "type": "address",
        "internalType": "address"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "approveCancellation",
    "inputs": [
      {
        "name": "_reasonHash",
        "type": "bytes32",
        "internalType": "bytes32"
      },
      {
        "name": "_signatures",
        "type": "tuple[]",
        "internalType": "struct ProjectEscrow.Signature[]",
        "components": [
          {
            "name": "signer",
            "type": "address",
            "internalType": "address"
          },
          {
            "name": "signature",
            "type": "bytes",
            "internalType": "bytes"
          }
        ]
      }
    ],
    "outputs": [],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "approveMilestone",
    "inputs": [
      {
        "name": "_signatures",
        "type": "tuple[]",
        "internalType": "struct ProjectEscrow.Signature[]",
        "components": [
          {
            "name": "signer",
            "type": "address",
            "internalType": "address"
          },
          {
            "name": "signature",
            "type": "bytes",
            "internalType": "bytes"
          }
        ]
      }
    ],
    "outputs": [],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "builderSigner",
    "inputs": [],
    "outputs": [
      {
        "name": "",
        "type": "address",
        "internalType": "address"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "cancellationApprovalCount",
    "inputs": [],
    "outputs": [
      {
        "name": "",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "cancellationNonces",
    "inputs": [
      {
        "name": "signer",
        "type": "address",
        "internalType": "address"
      }
    ],
    "outputs": [
      {
        "name": "nonce",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "cancellationReasonHash",
    "inputs": [],
    "outputs": [
      {
        "name": "",
        "type": "bytes32",
        "internalType": "bytes32"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "cancelled",
    "inputs": [],
    "outputs": [
      {
        "name": "",
        "type": "bool",
        "internalType": "bool"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "collectFees",
    "inputs": [],
    "outputs": [],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "committeeFeePerSignature",
    "inputs": [],
    "outputs": [
      {
        "name": "",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "committeeFinalized",
    "inputs": [],
    "outputs": [
      {
        "name": "",
        "type": "bool",
        "internalType": "bool"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "currentMilestoneIndex",
    "inputs": [],
    "outputs": [
      {
        "name": "",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "domainSeparator",
    "inputs": [],
    "outputs": [
      {
        "name": "",
        "type": "bytes32",
        "internalType": "bytes32"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "eip712Domain",
    "inputs": [],
    "outputs": [
      {
        "name": "fields",
        "type": "bytes1",
        "internalType": "bytes1"
      },
      {
        "name": "name",
        "type": "string",
        "internalType": "string"
      },
      {
        "name": "version",
        "type": "string",
        "internalType": "string"
      },
      {
        "name": "chainId",
        "type": "uint256",
        "internalType": "uint256"
      },
      {
        "name": "verifyingContract",
        "type": "address",
        "internalType": "address"
      },
      {
        "name": "salt",
        "type": "bytes32",
        "internalType": "bytes32"
      },
      {
        "name": "extensions",
        "type": "uint256[]",
        "internalType": "uint256[]"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "feeCredits",
    "inputs": [
      {
        "name": "",
        "type": "address",
        "internalType": "address"
      }
    ],
    "outputs": [
      {
        "name": "",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "feeReserve",
    "inputs": [],
    "outputs": [
      {
        "name": "",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "feesCollected",
    "inputs": [],
    "outputs": [
      {
        "name": "",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "getAlternatePromotionDigest",
    "inputs": [
      {
        "name": "_alternateIndex",
        "type": "uint256",
        "internalType": "uint256"
      },
      {
        "name": "_memberIndex",
        "type": "uint256",
        "internalType": "uint256"
      },
      {
        "name": "_signer",
        "type": "address",
        "internalType": "address"
      }
    ],
    "outputs": [
      {
        "name": "",
        "type": "bytes32",
        "internalType": "bytes32"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "getAlternates",
    "inputs": [],
    "outputs": [
      {
        "name": "",
        "type": "address[]",
        "internalType": "address[]"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "getCancellationApprovalDigest",
    "inputs": [
      {
        "name": "_reasonHash",
        "type": "bytes32",
        "internalType": "bytes32"
      },
      {
        "name": "_signer",
        "type": "address",
        "internalType": "address"
      }
    ],
    "outputs": [
      {
        "name": "",
        "type": "bytes32",
        "internalType": "bytes32"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "getMemberSigners",
    "inputs": [],
    "outputs": [
      {
        "name": "",
        "type": "address[]",
        "internalType": "address[]"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "getMilestoneApprovalDigest",
    "inputs": [
      {
        "name": "_milestoneIndex",
        "type": "uint256",
        "internalType": "uint256"
      },
      {
        "name": "_evidenceHash",
        "type": "bytes32",
        "internalType": "bytes32"
      },
      {
        "name": "_signer",
        "type": "address",
        "internalType": "address"
      }
    ],
    "outputs": [
      {
        "name": "",
        "type": "bytes32",
        "internalType": "bytes32"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "hasSigned",
    "inputs": [
      {
        "name": "_milestoneIndex",
        "type": "uint256",
        "internalType": "uint256"
      },
      {
        "name": "_signer",
        "type": "address",
        "internalType": "address"
      }
    ],
    "outputs": [
      {
        "name": "",
        "type": "bool",
        "internalType": "bool"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "hasSignedCancellation",
    "inputs": [
      {
        "name": "_signer",
        "type": "address",
        "internalType": "address"
      }
    ],
    "outputs": [
      {
        "name": "",
        "type": "bool",
        "internalType": "bool"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "initialize",
    "inputs": [
      {
        "name": "_projectWallet",
        "type": "address",
        "internalType": "address"
      },
      {
        "name": "_treasuryWallet",
        "type": "address",
        "internalType": "address"
      },
      {
        "name": "_token",
        "type": "address",
        "internalType": "address"
      },
      {
        "name": "_adminSigner",
        "type": "address",
        "internalType": "address"
      },
      {
        "name": "_builderSigner",
        "type": "address",
        "internalType": "address"
      },
      {
        "name": "_totalProjectBudget",
        "type": "uint256",
        "internalType": "uint256"
      },
      {
        "name": "_milestoneAmounts",
        "type": "uint256[]",
        "internalType": "uint256[]"
      },
      {
        "name": "_committeeFeePerSignature",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "outputs": [],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "isSigner",
    "inputs": [
      {
        "name": "_account",
        "type": "address",
        "internalType": "address"
      }
    ],
    "outputs": [
      {
        "name": "",
        "type": "bool",
        "internalType": "bool"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "memberSigners",
    "inputs": [
      {
        "name": "",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "outputs": [
      {
        "name": "",
        "type": "address",
        "internalType": "address"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "milestoneNonces",
    "inputs": [
      {
        "name": "signer",
        "type": "address",
        "internalType": "address"
      },
      {
        "name": "milestone",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "outputs": [
      {
        "name": "nonce",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "milestones",
    "inputs": [
      {
        "name": "",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "outputs": [
      {
        "name": "amount",
        "type": "uint256",
        "internalType": "uint256"
      },
      {
        "name": "evidenceHash",
        "type": "bytes32",
        "internalType": "bytes32"
      },
      {
        "name": "released",
        "type": "bool",
        "internalType": "bool"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "projectGovernanceContract",
    "inputs": [],
    "outputs": [
      {
        "name": "",
        "type": "address",
        "internalType": "address"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "projectWallet",
    "inputs": [],
    "outputs": [
      {
        "name": "",
        "type": "address",
        "internalType": "address"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "promoteAlternate",
    "inputs": [
      {
        "name": "_alternateIndex",
        "type": "uint256",
        "internalType": "uint256"
      },
      {
        "name": "_memberIndex",
        "type": "uint256",
        "internalType": "uint256"
      },
      {
        "name": "_signatures",
        "type": "tuple[]",
        "internalType": "struct ProjectEscrow.Signature[]",
        "components": [
          {
            "name": "signer",
            "type": "address",
            "internalType": "address"
          },
          {
            "name": "signature",
            "type": "bytes",
            "internalType": "bytes"
          }
        ]
      }
    ],
    "outputs": [],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "promotionNonces",
    "inputs": [
      {
        "name": "signer",
        "type": "address",
        "internalType": "address"
      }
    ],
    "outputs": [
      {
        "name": "nonce",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "releaseDeposit",
    "inputs": [],
    "outputs": [],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "releaseSettlement",
    "inputs": [
      {
        "name": "_settlementAmount",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "outputs": [],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "setCommitteeMembers",
    "inputs": [
      {
        "name": "_members",
        "type": "address[]",
        "internalType": "address[]"
      },
      {
        "name": "_alternates",
        "type": "address[]",
        "internalType": "address[]"
      }
    ],
    "outputs": [],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "settlementPaid",
    "inputs": [],
    "outputs": [
      {
        "name": "",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "submitMilestoneComplete",
    "inputs": [
      {
        "name": "_evidenceHash",
        "type": "bytes32",
        "internalType": "bytes32"
      }
    ],
    "outputs": [],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "sweepSurplusToTreasury",
    "inputs": [],
    "outputs": [],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "token",
    "inputs": [],
    "outputs": [
      {
        "name": "",
        "type": "address",
        "internalType": "contract IPaymentToken"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "totalProjectBudget",
    "inputs": [],
    "outputs": [
      {
        "name": "",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "totalReleased",
    "inputs": [],
    "outputs": [
      {
        "name": "",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "totalReturnedOnCancellation",
    "inputs": [],
    "outputs": [
      {
        "name": "",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "totalSweptToTreasury",
    "inputs": [],
    "outputs": [
      {
        "name": "",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "totalUncollectedFees",
    "inputs": [],
    "outputs": [
      {
        "name": "",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "treasuryWallet",
    "inputs": [],
    "outputs": [
      {
        "name": "",
        "type": "address",
        "internalType": "address"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "event",
    "name": "AlternatePromoted",
    "inputs": [
      {
        "name": "memberIndex",
        "type": "uint256",
        "indexed": true,
        "internalType": "uint256"
      },
      {
        "name": "promotedMember",
        "type": "address",
        "indexed": true,
        "internalType": "address"
      }
    ],
    "anonymous": false
  },
  {
    "type": "event",
    "name": "CancellationApproved",
    "inputs": [
      {
        "name": "signer",
        "type": "address",
        "indexed": true,
        "internalType": "address"
      },
      {
        "name": "reasonHash",
        "type": "bytes32",
        "indexed": false,
        "internalType": "bytes32"
      }
    ],
    "anonymous": false
  },
  {
    "type": "event",
    "name": "CommitteeFeeAccrued",
    "inputs": [
      {
        "name": "milestoneIndex",
        "type": "uint256",
        "indexed": true,
        "internalType": "uint256"
      },
      {
        "name": "member",
        "type": "address",
        "indexed": true,
        "internalType": "address"
      },
      {
        "name": "amount",
        "type": "uint256",
        "indexed": false,
        "internalType": "uint256"
      }
    ],
    "anonymous": false
  },
  {
    "type": "event",
    "name": "CommitteeFinalized",
    "inputs": [
      {
        "name": "members",
        "type": "address[]",
        "indexed": false,
        "internalType": "address[]"
      },
      {
        "name": "alternates",
        "type": "address[]",
        "indexed": false,
        "internalType": "address[]"
      }
    ],
    "anonymous": false
  },
  {
    "type": "event",
    "name": "EIP712DomainChanged",
    "inputs": [],
    "anonymous": false
  },
  {
    "type": "event",
    "name": "FeesCollected",
    "inputs": [
      {
        "name": "member",
        "type": "address",
        "indexed": true,
        "internalType": "address"
      },
      {
        "name": "amount",
        "type": "uint256",
        "indexed": false,
        "internalType": "uint256"
      }
    ],
    "anonymous": false
  },
  {
    "type": "event",
    "name": "Initialized",
    "inputs": [
      {
        "name": "version",
        "type": "uint64",
        "indexed": false,
        "internalType": "uint64"
      }
    ],
    "anonymous": false
  },
  {
    "type": "event",
    "name": "MilestoneApproved",
    "inputs": [
      {
        "name": "milestoneIndex",
        "type": "uint256",
        "indexed": true,
        "internalType": "uint256"
      },
      {
        "name": "signer",
        "type": "address",
        "indexed": true,
        "internalType": "address"
      }
    ],
    "anonymous": false
  },
  {
    "type": "event",
    "name": "MilestoneCompletionSubmitted",
    "inputs": [
      {
        "name": "milestoneIndex",
        "type": "uint256",
        "indexed": true,
        "internalType": "uint256"
      },
      {
        "name": "evidenceHash",
        "type": "bytes32",
        "indexed": false,
        "internalType": "bytes32"
      }
    ],
    "anonymous": false
  },
  {
    "type": "event",
    "name": "MilestoneReleased",
    "inputs": [
      {
        "name": "milestoneIndex",
        "type": "uint256",
        "indexed": true,
        "internalType": "uint256"
      },
      {
        "name": "projectWallet",
        "type": "address",
        "indexed": true,
        "internalType": "address"
      },
      {
        "name": "amount",
        "type": "uint256",
        "indexed": false,
        "internalType": "uint256"
      }
    ],
    "anonymous": false
  },
  {
    "type": "event",
    "name": "ProjectTerminated",
    "inputs": [
      {
        "name": "treasuryWallet",
        "type": "address",
        "indexed": true,
        "internalType": "address"
      },
      {
        "name": "returnedAmount",
        "type": "uint256",
        "indexed": false,
        "internalType": "uint256"
      }
    ],
    "anonymous": false
  },
  {
    "type": "event",
    "name": "SettlementPaid",
    "inputs": [
      {
        "name": "amount",
        "type": "uint256",
        "indexed": false,
        "internalType": "uint256"
      }
    ],
    "anonymous": false
  },
  {
    "type": "event",
    "name": "SurplusSwept",
    "inputs": [
      {
        "name": "treasuryWallet",
        "type": "address",
        "indexed": true,
        "internalType": "address"
      },
      {
        "name": "amount",
        "type": "uint256",
        "indexed": false,
        "internalType": "uint256"
      }
    ],
    "anonymous": false
  },
  {
    "type": "error",
    "name": "AccountingMismatch",
    "inputs": []
  },
  {
    "type": "error",
    "name": "AddressZero",
    "inputs": []
  },
  {
    "type": "error",
    "name": "AllMilestonesReleased",
    "inputs": []
  },
  {
    "type": "error",
    "name": "AlreadySigned",
    "inputs": []
  },
  {
    "type": "error",
    "name": "BuilderMustSubmitDirectly",
    "inputs": []
  },
  {
    "type": "error",
    "name": "BuilderMustSubmitFirst",
    "inputs": []
  },
  {
    "type": "error",
    "name": "CommitteeAlreadyFinalized",
    "inputs": []
  },
  {
    "type": "error",
    "name": "CommitteeNotFinalized",
    "inputs": []
  },
  {
    "type": "error",
    "name": "DuplicateSigner",
    "inputs": []
  },
  {
    "type": "error",
    "name": "InvalidAlternateIndex",
    "inputs": []
  },
  {
    "type": "error",
    "name": "InvalidHash",
    "inputs": []
  },
  {
    "type": "error",
    "name": "InvalidInitialization",
    "inputs": []
  },
  {
    "type": "error",
    "name": "InvalidMemberIndex",
    "inputs": []
  },
  {
    "type": "error",
    "name": "InvalidMilestoneCount",
    "inputs": []
  },
  {
    "type": "error",
    "name": "InvalidShortString",
    "inputs": []
  },
  {
    "type": "error",
    "name": "InvalidSignature",
    "inputs": []
  },
  {
    "type": "error",
    "name": "MilestoneAlreadyReleased",
    "inputs": []
  },
  {
    "type": "error",
    "name": "MilestonesDontMatchBudget",
    "inputs": []
  },
  {
    "type": "error",
    "name": "NoAlternates",
    "inputs": []
  },
  {
    "type": "error",
    "name": "NoMilestones",
    "inputs": []
  },
  {
    "type": "error",
    "name": "NotBuilder",
    "inputs": []
  },
  {
    "type": "error",
    "name": "NotInitializing",
    "inputs": []
  },
  {
    "type": "error",
    "name": "NotSigner",
    "inputs": []
  },
  {
    "type": "error",
    "name": "ProjectCancelled",
    "inputs": []
  },
  {
    "type": "error",
    "name": "ProjectStillActive",
    "inputs": []
  },
  {
    "type": "error",
    "name": "ReasonMismatch",
    "inputs": []
  },
  {
    "type": "error",
    "name": "ReentrancyGuardReentrantCall",
    "inputs": []
  },
  {
    "type": "error",
    "name": "SafeERC20FailedOperation",
    "inputs": [
      {
        "name": "token",
        "type": "address",
        "internalType": "address"
      }
    ]
  },
  {
    "type": "error",
    "name": "SettlementTooHigh",
    "inputs": []
  },
  {
    "type": "error",
    "name": "StringTooLong",
    "inputs": [
      {
        "name": "str",
        "type": "string",
        "internalType": "string"
      }
    ]
  },
  {
    "type": "error",
    "name": "TooManyAlternates",
    "inputs": []
  },
  {
    "type": "error",
    "name": "TooManyMembers",
    "inputs": []
  },
  {
    "type": "error",
    "name": "UnauthorisedCalled",
    "inputs": []
  },
  {
    "type": "error",
    "name": "ZeroAmount",
    "inputs": []
  },
  {
    "type": "error",
    "name": "ZeroBudget",
    "inputs": []
  }
] as const;
