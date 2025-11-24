# HarbergerNFTs

A Harberger tax NFT implementation built with Solidity and Foundry. This contract implements a continuous ownership model where NFT owners must pay periodic taxes, and NFTs can be purchased at any time for their listed price.

## Prerequisites

Before you begin you'll neeed foundry installed here: [Foundry](https://book.getfoundry.sh/getting-started/installation).

To install, run:

```bash
curl -L https://foundry.paradigm.xyz | bash
foundryup
```

## Install Dependencies

To install all dependencies run:

```bash
forge install
```

## Compilation

To compile smart contracts:

```bash
forge build
```

## Testing

To run all tests:

```bash
forge test
```

To run w/ gas reporting:

```bash
forge test --gas-report
```

## Built with love by @immaxkent
