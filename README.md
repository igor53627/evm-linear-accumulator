# evm-linear-accumulator

Gas-optimized linear hash accumulator over Z_q for on-chain integrity checking.

## What it does

Computes `H(x) = A * x mod q` where `A` is an NxN (up to 64x64) full-rank matrix derived deterministically from a seed via `keccak256`. The matrix is never stored -- it is recomputed during evaluation.

## Use cases

- **Trace integrity / wire binding** (TLOS) -- verify execution traces have not been spliced
- **State accumulators** -- fold sequential state updates into a compact digest
- **Fraud proof integrity** -- bind computation steps to prevent selective replay
- **Incremental hashing** -- update accumulator as new data arrives via `update()`

## Core API

```solidity
import {LibLinearAccumulator} from "evm-linear-accumulator/src/LibLinearAccumulator.sol";

// Compute H(x) = A * x mod q (q defaults to 65521)
uint256[4] memory result = LibLinearAccumulator.accumulate(inputBits, stepIndex, numRows, seed);

// With custom modulus
uint256[4] memory result = LibLinearAccumulator.accumulate(inputBits, stepIndex, numRows, seed, q);

// Fold new input into existing accumulator
uint256[4] memory updated = LibLinearAccumulator.update(acc, newInput, stepIndex, numRows, seed);

// XOR all words together
uint256 combined = LibLinearAccumulator.xorAll(result);
```

### Parameters

| Parameter | Description | Range |
|-----------|-------------|-------|
| `inputBits` | Bit-vector input (lower N bits used) | uint256 |
| `stepIndex` | Matrix derivation index (e.g. batch number) | uint256 |
| `numRows` | Matrix dimension N | 1-64 |
| `seed` | Domain seed for deterministic matrix derivation | bytes32 |
| `q` | Modulus (optional, default 65521) | 1-65521 |

### Output format

Output is `uint256[4]` -- 4 words packing up to 64 elements of 16 bits each (16 elements per word).

## Usage as dependency

```bash
forge install <org>/evm-linear-accumulator
```

```solidity
import {LibLinearAccumulator} from "evm-linear-accumulator/src/LibLinearAccumulator.sol";
```

## Build & test

```bash
forge build
forge test -vv
```

## Gas benchmarks

| Operation | Dimension | Gas |
|-----------|----------|-----|
| `accumulate` | 64x64 | ~840K-1.5M |
| `accumulate` | 4x4 | ~10K |
| `accumulate` | 1x1 | ~5K |
| `update` | 64x64 | ~1.4M |
| `xorAll` | - | ~4K |

## Matrix derivation

The matrix `A` is derived deterministically:
1. Row seed: `keccak256(seed || stepIndex || row)`
2. Block digest: `keccak256(rowSeed || blockIdx)`
3. Coefficients: 16 x 16-bit values extracted from each block digest, reduced mod q

This means the matrix is never stored -- it is recomputed during evaluation, saving storage at the cost of computation.

## Properties

- **Binding:** Full-rank matrix over Z_q is bijective (unique preimage for any output)
- **Deterministic:** Same inputs always produce the same output
- **NOT collision-resistant:** The linear system is trivially invertible; this is an integrity check, not a hash function

## Related projects

- [tlos](https://github.com/igor53627/tlos) -- Topology-Lattice Obfuscation (original wire binding consumer)
- [evm-lwe-math](https://github.com/igor53627/evm-lwe-math) -- LWE inner-product primitives

## License

MIT
