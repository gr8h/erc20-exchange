# SimpleDEX: A Simple Decentralized Exchange for ERC20 Tokens

## Overview

SimpleDEX is a decentralized exchange (DEX) for trading ERC20 tokens. It aims to provide a straightforward and secure trading platform that allows for off-chain order creation and on-chain order settlement.

## Features

- **Support for Multiple Tokens**: Add any ERC20 token to the list of tradable assets.
- **Deposit and Withdrawal**: Users can deposit tokens into and withdraw tokens from the exchange.
- **Order Matching**: Off-chain created orders can be matched and settled on-chain.
- **Signature Verification**: Ensures that orders are valid and come from the correct sender.
- **Nonce Tracking**: Ensures that an order is only used once.
- **Order Expiry**: Orders can be set to expire after a certain timestamp.

## Smart Contract Structure

- **State Variables**:

  - `supportedTokens`: A mapping to keep track of all supported ERC20 tokens.
  - `userBalances`: A nested mapping to keep track of user balances for each token.
  - `usedNonces`: A nested mapping to keep track of used nonces to prevent replay attacks.

- **Modifiers**:

  - `orderNotExpired`: Checks whether an order has expired.

- **Events**:

  - `TokenAdded`, `Deposited`, `Withdrawn`, `OrderMatched`: Emitted during respective state changes.

- **Errors**:
  - Custom errors for better debugging, including `TokenNotSupported`, `InsufficientBalance`, `OrderExpired`, etc.

## Prerequisites

This project requires the use of [Foundry](https://book.getfoundry.sh/)

## Installing

```
forge install
forge build
```

## Running the tests

```
forge test -vv
```

### Test coverage

```
forge coverage --report lcov && genhtml --ignore-errors category lcov.info --branch-coverage --output-dir coverage
```

## Deployment

### Gorli

- To load the variables in the .env file

```
source .env
```

- To deploy

```
forge script script/SimpleDEX.s.sol --rpc-url $GOERLI_RPC_URL --broadcast --verify -vvvv
```

- [Deployed contract](https://goerli.etherscan.io/address/0x06a60d0038c03e185ae0c121eee30e4d1faa6c6c)

## Limitations & Future Work

- Currently, the contract owner is the only one who can match orders. Future versions could allow for decentralized order matching.
- The contract does not yet support limit orders or more complex trading features.
