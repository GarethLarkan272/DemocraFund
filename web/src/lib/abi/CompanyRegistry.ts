export const CompanyRegistryAbi = [
  {
    "type": "function",
    "name": "companies",
    "inputs": [
      {
        "name": "companyId",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "outputs": [
      {
        "name": "adminWallet",
        "type": "address",
        "internalType": "address"
      },
      {
        "name": "infoHash",
        "type": "bytes32",
        "internalType": "bytes32"
      },
      {
        "name": "active",
        "type": "bool",
        "internalType": "bool"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "companyCount",
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
    "name": "companyIdOfAdmin",
    "inputs": [
      {
        "name": "adminWallet",
        "type": "address",
        "internalType": "address"
      }
    ],
    "outputs": [
      {
        "name": "companyId",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "registerCompany",
    "inputs": [
      {
        "name": "_infoHash",
        "type": "bytes32",
        "internalType": "bytes32"
      }
    ],
    "outputs": [
      {
        "name": "companyId",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "setCompanyActive",
    "inputs": [
      {
        "name": "_active",
        "type": "bool",
        "internalType": "bool"
      }
    ],
    "outputs": [],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "updateCompany",
    "inputs": [
      {
        "name": "_infoHash",
        "type": "bytes32",
        "internalType": "bytes32"
      }
    ],
    "outputs": [],
    "stateMutability": "nonpayable"
  },
  {
    "type": "event",
    "name": "CompanyActivated",
    "inputs": [
      {
        "name": "companyId",
        "type": "uint256",
        "indexed": true,
        "internalType": "uint256"
      },
      {
        "name": "active",
        "type": "bool",
        "indexed": false,
        "internalType": "bool"
      }
    ],
    "anonymous": false
  },
  {
    "type": "event",
    "name": "CompanyRegistered",
    "inputs": [
      {
        "name": "companyId",
        "type": "uint256",
        "indexed": true,
        "internalType": "uint256"
      },
      {
        "name": "adminWallet",
        "type": "address",
        "indexed": true,
        "internalType": "address"
      },
      {
        "name": "infoHash",
        "type": "bytes32",
        "indexed": false,
        "internalType": "bytes32"
      }
    ],
    "anonymous": false
  },
  {
    "type": "event",
    "name": "CompanyUpdated",
    "inputs": [
      {
        "name": "companyId",
        "type": "uint256",
        "indexed": true,
        "internalType": "uint256"
      },
      {
        "name": "infoHash",
        "type": "bytes32",
        "indexed": false,
        "internalType": "bytes32"
      }
    ],
    "anonymous": false
  },
  {
    "type": "error",
    "name": "AlreadyRegistered",
    "inputs": []
  },
  {
    "type": "error",
    "name": "CompanyNotActive",
    "inputs": []
  },
  {
    "type": "error",
    "name": "CompanyStateUnchanged",
    "inputs": []
  },
  {
    "type": "error",
    "name": "InvalidHash",
    "inputs": []
  },
  {
    "type": "error",
    "name": "NotRegistered",
    "inputs": []
  }
] as const;
