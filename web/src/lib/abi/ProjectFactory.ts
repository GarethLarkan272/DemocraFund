export const ProjectFactoryAbi = [
  {
    "type": "constructor",
    "inputs": [
      {
        "name": "_globalMinimumVotingDuration",
        "type": "uint256",
        "internalType": "uint256"
      },
      {
        "name": "_minimumProposalSubmissionDuration",
        "type": "uint64",
        "internalType": "uint64"
      },
      {
        "name": "_minimumVotingDuration",
        "type": "uint64",
        "internalType": "uint64"
      },
      {
        "name": "_paymentToken",
        "type": "address",
        "internalType": "address"
      },
      {
        "name": "_escrowImplementation",
        "type": "address",
        "internalType": "address"
      },
      {
        "name": "_createProjectSafeWallet",
        "type": "address",
        "internalType": "address"
      },
      {
        "name": "_companyRegistry",
        "type": "address",
        "internalType": "address"
      },
      {
        "name": "_vrfConfig",
        "type": "tuple",
        "internalType": "struct IProjectConfig.VRFConfig",
        "components": [
          {
            "name": "subscriptionId",
            "type": "uint256",
            "internalType": "uint256"
          },
          {
            "name": "keyHash",
            "type": "bytes32",
            "internalType": "bytes32"
          },
          {
            "name": "coordinator",
            "type": "address",
            "internalType": "address"
          },
          {
            "name": "callbackGasLimit",
            "type": "uint32",
            "internalType": "uint32"
          },
          {
            "name": "requestConfirmations",
            "type": "uint16",
            "internalType": "uint16"
          },
          {
            "name": "nativePayment",
            "type": "bool",
            "internalType": "bool"
          }
        ]
      }
    ],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "CREATE_PROJECT_ROLE",
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
    "name": "DEFAULT_ADMIN_ROLE",
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
    "name": "MAX_COMMITTEE_FEE_PER_SIGNATURE",
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
    "name": "PROJECT_ESCROW_IMPLEMENTATION",
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
    "name": "companyRegistry",
    "inputs": [],
    "outputs": [
      {
        "name": "",
        "type": "address",
        "internalType": "contract CompanyRegistry"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "createProject",
    "inputs": [
      {
        "name": "_config",
        "type": "tuple",
        "internalType": "struct IProjectConfig.ProjectConfig",
        "components": [
          {
            "name": "budgetCap",
            "type": "uint256",
            "internalType": "uint256"
          },
          {
            "name": "committeeFeePerSignature",
            "type": "uint256",
            "internalType": "uint256"
          },
          {
            "name": "title",
            "type": "bytes32",
            "internalType": "bytes32"
          },
          {
            "name": "category",
            "type": "bytes32",
            "internalType": "bytes32"
          },
          {
            "name": "department",
            "type": "bytes32",
            "internalType": "bytes32"
          },
          {
            "name": "specContentHash",
            "type": "bytes32",
            "internalType": "bytes32"
          },
          {
            "name": "ipfsHash",
            "type": "bytes32",
            "internalType": "bytes32"
          },
          {
            "name": "proposalDeadline",
            "type": "uint64",
            "internalType": "uint64"
          },
          {
            "name": "votingDeadline",
            "type": "uint64",
            "internalType": "uint64"
          },
          {
            "name": "deliberationWindow",
            "type": "uint64",
            "internalType": "uint64"
          },
          {
            "name": "governanceSafeWallet",
            "type": "address",
            "internalType": "address"
          },
          {
            "name": "treasuryWallet",
            "type": "address",
            "internalType": "address"
          }
        ]
      }
    ],
    "outputs": [
      {
        "name": "projectGovernanceInstanceAddr",
        "type": "address",
        "internalType": "address"
      }
    ],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "getRoleAdmin",
    "inputs": [
      {
        "name": "role",
        "type": "bytes32",
        "internalType": "bytes32"
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
    "name": "globalMinimumVotingDuration",
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
    "name": "grantRole",
    "inputs": [
      {
        "name": "role",
        "type": "bytes32",
        "internalType": "bytes32"
      },
      {
        "name": "account",
        "type": "address",
        "internalType": "address"
      }
    ],
    "outputs": [],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "hasRole",
    "inputs": [
      {
        "name": "role",
        "type": "bytes32",
        "internalType": "bytes32"
      },
      {
        "name": "account",
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
    "name": "isProject",
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
        "type": "bool",
        "internalType": "bool"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "minimumProposalSubmissionDuration",
    "inputs": [],
    "outputs": [
      {
        "name": "",
        "type": "uint64",
        "internalType": "uint64"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "minimumVotingDuration",
    "inputs": [],
    "outputs": [
      {
        "name": "",
        "type": "uint64",
        "internalType": "uint64"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "mintInitialSupplyForProject",
    "inputs": [
      {
        "name": "_projectEscrow",
        "type": "address",
        "internalType": "address"
      },
      {
        "name": "_amount",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "outputs": [],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "projectCount",
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
    "name": "renounceRole",
    "inputs": [
      {
        "name": "role",
        "type": "bytes32",
        "internalType": "bytes32"
      },
      {
        "name": "callerConfirmation",
        "type": "address",
        "internalType": "address"
      }
    ],
    "outputs": [],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "revokeRole",
    "inputs": [
      {
        "name": "role",
        "type": "bytes32",
        "internalType": "bytes32"
      },
      {
        "name": "account",
        "type": "address",
        "internalType": "address"
      }
    ],
    "outputs": [],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "supportsInterface",
    "inputs": [
      {
        "name": "interfaceId",
        "type": "bytes4",
        "internalType": "bytes4"
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
    "name": "token",
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
    "name": "updateGlobalMinimumVotingDuration",
    "inputs": [
      {
        "name": "_newGlobalMinimum",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "outputs": [],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "vrfConfig",
    "inputs": [],
    "outputs": [
      {
        "name": "subscriptionId",
        "type": "uint256",
        "internalType": "uint256"
      },
      {
        "name": "keyHash",
        "type": "bytes32",
        "internalType": "bytes32"
      },
      {
        "name": "coordinator",
        "type": "address",
        "internalType": "address"
      },
      {
        "name": "callbackGasLimit",
        "type": "uint32",
        "internalType": "uint32"
      },
      {
        "name": "requestConfirmations",
        "type": "uint16",
        "internalType": "uint16"
      },
      {
        "name": "nativePayment",
        "type": "bool",
        "internalType": "bool"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "event",
    "name": "GlobalMinimumVotingDurationUpdated",
    "inputs": [
      {
        "name": "newGlobalMinimum",
        "type": "uint256",
        "indexed": false,
        "internalType": "uint256"
      }
    ],
    "anonymous": false
  },
  {
    "type": "event",
    "name": "ProjectCreated",
    "inputs": [
      {
        "name": "projectInstance",
        "type": "address",
        "indexed": true,
        "internalType": "address"
      }
    ],
    "anonymous": false
  },
  {
    "type": "event",
    "name": "ProjectFunded",
    "inputs": [
      {
        "name": "projectEscrow",
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
    "name": "RoleAdminChanged",
    "inputs": [
      {
        "name": "role",
        "type": "bytes32",
        "indexed": true,
        "internalType": "bytes32"
      },
      {
        "name": "previousAdminRole",
        "type": "bytes32",
        "indexed": true,
        "internalType": "bytes32"
      },
      {
        "name": "newAdminRole",
        "type": "bytes32",
        "indexed": true,
        "internalType": "bytes32"
      }
    ],
    "anonymous": false
  },
  {
    "type": "event",
    "name": "RoleGranted",
    "inputs": [
      {
        "name": "role",
        "type": "bytes32",
        "indexed": true,
        "internalType": "bytes32"
      },
      {
        "name": "account",
        "type": "address",
        "indexed": true,
        "internalType": "address"
      },
      {
        "name": "sender",
        "type": "address",
        "indexed": true,
        "internalType": "address"
      }
    ],
    "anonymous": false
  },
  {
    "type": "event",
    "name": "RoleRevoked",
    "inputs": [
      {
        "name": "role",
        "type": "bytes32",
        "indexed": true,
        "internalType": "bytes32"
      },
      {
        "name": "account",
        "type": "address",
        "indexed": true,
        "internalType": "address"
      },
      {
        "name": "sender",
        "type": "address",
        "indexed": true,
        "internalType": "address"
      }
    ],
    "anonymous": false
  },
  {
    "type": "error",
    "name": "AccessControlBadConfirmation",
    "inputs": []
  },
  {
    "type": "error",
    "name": "AccessControlUnauthorizedAccount",
    "inputs": [
      {
        "name": "account",
        "type": "address",
        "internalType": "address"
      },
      {
        "name": "neededRole",
        "type": "bytes32",
        "internalType": "bytes32"
      }
    ]
  },
  {
    "type": "error",
    "name": "AddressZero",
    "inputs": []
  },
  {
    "type": "error",
    "name": "FeeTooHigh",
    "inputs": []
  },
  {
    "type": "error",
    "name": "InvalidCategory",
    "inputs": []
  },
  {
    "type": "error",
    "name": "InvalidDeliberationWindow",
    "inputs": []
  },
  {
    "type": "error",
    "name": "InvalidDepartment",
    "inputs": []
  },
  {
    "type": "error",
    "name": "InvalidHash",
    "inputs": []
  },
  {
    "type": "error",
    "name": "InvalidProposalSubmissionDuration",
    "inputs": []
  },
  {
    "type": "error",
    "name": "InvalidTitle",
    "inputs": []
  },
  {
    "type": "error",
    "name": "InvalidVRFConfig",
    "inputs": []
  },
  {
    "type": "error",
    "name": "InvalidVotingDuration",
    "inputs": []
  },
  {
    "type": "error",
    "name": "ProjectNonExistent",
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
