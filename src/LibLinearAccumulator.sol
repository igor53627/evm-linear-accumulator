// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title LibLinearAccumulator
/// @notice Gas-optimized linear hash accumulator over Z_q using seed-derived matrices.
/// @dev Computes H(x) = A * x mod q where A is an NxN matrix derived deterministically from a seed.
///      Matrix is overwhelmingly likely full-rank for hash-derived entries (especially over
///      prime moduli), but callers requiring guaranteed invertibility should verify off-chain.
///      Each matrix row is derived via keccak256(seed || stepIndex || row || blockIdx).
///      Output is packed as 16-bit elements into uint256 words (16 elements per word).
///
///      General-purpose primitive useful for:
///        - Trace integrity / wire binding (TLOS)
///        - State accumulators
///        - Fraud proof integrity checks
///        - Incremental hashing over finite fields
library LibLinearAccumulator {
    uint256 internal constant DEFAULT_Q = 65521;

    /// @notice Computes H(x) = A * x mod q for an NxN matrix.
    /// @param inputBits Bit-vector input (lower `numRows` bits are used as x)
    /// @param stepIndex Index for matrix derivation (e.g. gate index, batch index)
    /// @param numRows Matrix dimension N (1-64). Also determines number of output elements.
    /// @param seed Domain seed for deterministic matrix derivation
    /// @param q Modulus (must be <= 65521 to fit in 16-bit lanes)
    /// @return output Packed output: ceil(N/16) uint256 words, 16-bit elements per word
    function accumulate(
        uint256 inputBits,
        uint256 stepIndex,
        uint256 numRows,
        bytes32 seed,
        uint256 q
    ) internal pure returns (uint256[4] memory output) {
        require(numRows > 0 && numRows <= 64, "numRows must be 1-64");
        require(q >= 2 && q <= 65521, "q must be 2-65521");
        return _accumulate(inputBits, stepIndex, numRows, seed, q);
    }

    /// @notice Convenience: accumulate with default q=65521 (largest 16-bit prime).
    function accumulate(
        uint256 inputBits,
        uint256 stepIndex,
        uint256 numRows,
        bytes32 seed
    ) internal pure returns (uint256[4] memory) {
        require(numRows > 0 && numRows <= 64, "numRows must be 1-64");
        return _accumulate(inputBits, stepIndex, numRows, seed, DEFAULT_Q);
    }

    /// @dev Core assembly implementation. Callers must validate inputs.
    function _accumulate(
        uint256 inputBits,
        uint256 stepIndex,
        uint256 numRows,
        bytes32 seed,
        uint256 q
    ) private pure returns (uint256[4] memory output) {
        assembly {
            let outPtr := output
            for { let row := 0 } lt(row, numRows) { row := add(row, 1) } {
                let freePtr := mload(0x40)
                mstore(freePtr, seed)
                mstore(add(freePtr, 32), stepIndex)
                mstore(add(freePtr, 64), row)
                let rowSeed := keccak256(freePtr, 96)

                let sum := 0
                let col := 0
                for { let blockIdx := 0 } lt(col, numRows) { blockIdx := add(blockIdx, 1) } {
                    mstore(freePtr, rowSeed)
                    mstore(add(freePtr, 32), blockIdx)
                    let blockDigest := keccak256(freePtr, 64)

                    for { let k := 0 } and(lt(k, 16), lt(col, numRows)) { k := add(k, 1) } {
                        let aij := mod(and(shr(mul(k, 16), blockDigest), 0xFFFF), q)
                        let bitVal := and(shr(col, inputBits), 1)
                        if bitVal {
                            sum := add(sum, aij)
                            if iszero(lt(sum, q)) { sum := sub(sum, q) }
                        }
                        col := add(col, 1)
                    }
                }

                let wordIdx := div(row, 16)
                let bitPos := mul(mod(row, 16), 16)
                let wordPtr := add(outPtr, mul(wordIdx, 32))
                let existing := mload(wordPtr)
                mstore(wordPtr, or(existing, shl(bitPos, and(sum, 0xFFFF))))
            }
        }
    }

    /// @notice XOR all output words together into a single uint256.
    /// @dev Useful for combining accumulator state with other data.
    function xorAll(uint256[4] memory output) internal pure returns (uint256 result) {
        result = output[0] ^ output[1] ^ output[2] ^ output[3];
    }

    /// @notice Update accumulator: XOR current state with new input, re-accumulate (default q).
    function update(
        uint256[4] memory acc,
        uint256 newInput,
        uint256 stepIndex,
        uint256 numRows,
        bytes32 seed
    ) internal pure returns (uint256[4] memory) {
        uint256 combined = xorAll(acc) ^ newInput;
        return accumulate(combined, stepIndex, numRows, seed);
    }

    /// @notice Update accumulator with custom modulus.
    function update(
        uint256[4] memory acc,
        uint256 newInput,
        uint256 stepIndex,
        uint256 numRows,
        bytes32 seed,
        uint256 q
    ) internal pure returns (uint256[4] memory) {
        uint256 combined = xorAll(acc) ^ newInput;
        return accumulate(combined, stepIndex, numRows, seed, q);
    }
}
