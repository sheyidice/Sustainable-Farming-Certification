# 🌱 GreenCert - Sustainable Farming Certification Protocol

A blockchain-based protocol for issuing and verifying on-chain certifications for farms that meet specific sustainability criteria.

## 📋 Overview

GreenCert enables:
- 🚜 **Farm Registration**: Register farms with location and size details
- 🏅 **Certification Issuance**: Certify farms that meet sustainability criteria
- ✅ **Verification**: On-chain verification of farm certifications
- 👩‍🌾 **Authority Management**: Manage certification authorities
- ⏰ **Expiration Tracking**: Automatic certification expiration handling

## 🚀 Quick Start

### Prerequisites
- [Clarinet](https://github.com/hirosystems/clarinet) installed
- Stacks wallet for testing

### Installation
```bash
git clone https://github.com/your-repo/sustainable-farming-certification
cd sustainable-farming-certification
clarinet check
```

## 📖 Usage

### 🏠 Register a Farm
```clarity
(contract-call? .GreenCert register-farm "Green Valley Farm" "California, USA" u150)
```

### 🔐 Register as Certification Authority
```clarity
(contract-call? .GreenCert register-authority "Sustainable Agriculture Board")
```

### 🎖️ Issue Certification
```clarity
(contract-call? .GreenCert issue-certification u1 (list "organic" "water-efficient" "soil-health") u85)
```

### 📊 Check Certification Status
```clarity
(contract-call? .GreenCert get-certification-status u1)
```

### 🔍 Verify Farm Certification
```clarity
(contract-call? .GreenCert is-certified u1)
```

## 🛠️ Core Functions

### Public Functions
- `register-farm` - Register a new farm
- `register-authority` - Register certification authority (owner only)
- `issue-certification` - Issue certification to a farm
- `revoke-certification` - Revoke existing certification
- `suspend-authority` - Suspend certification authority (owner only)
- `update-farm-status` - Update farm active status
- `pay-certification-fee` - Pay certification fee
- `set-certification-fee` - Update certification fee (owner only)

### Read-Only Functions
- `get-farm` - Get farm details
- `get-certification` - Get certification details
- `get-authority` - Get authority details
- `is-certified` - Check if farm is currently certified
- `get-certification-status` - Get detailed certification status
- `get-farms-by-owner` - Get all farms owned by address
- `get-contract-stats` - Get contract statistics

## 📊 Data Structures

### Farm
```clarity
{
  owner: principal,
  name: string-ascii,
  location: string-ascii,
  size-hectares: uint,
  registered-at: uint,
  active: bool
}
```

### Certification
```clarity
{
  certification-id: uint,
  authority: principal,
  criteria-met: list of criteria,
  score: uint,
  issued-at: uint,
  expires-at: uint,
  valid: bool
}
```

## ⚙️ Configuration

- **Certification Duration**: 52,560 blocks (~1 year)
- **Default Fee**: 1,000,000 µSTX
- **Max Criteria per Certification**: 10
- **Max Score**: 100 points

## 🧪 Testing

Run the test suite:
```bash
clarinet test
```

## 📄 License

This project is licensed under the MIT License.

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Commit your changes
4. Push to the branch
5. Create a Pull Request

---

**Built with ❤️ for sustainable farming** 🌾
