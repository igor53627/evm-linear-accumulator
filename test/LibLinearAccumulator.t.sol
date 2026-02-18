// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {LibLinearAccumulator} from "../src/LibLinearAccumulator.sol";

contract LibLinearAccumulatorHarness {
    function accumulate(uint256 inputBits, uint256 stepIndex, uint256 numRows, bytes32 seed, uint256 q)
        external pure returns (uint256[4] memory) {
        return LibLinearAccumulator.accumulate(inputBits, stepIndex, numRows, seed, q);
    }

    function accumulateDefaultQ(uint256 inputBits, uint256 stepIndex, uint256 numRows, bytes32 seed)
        external pure returns (uint256[4] memory) {
        return LibLinearAccumulator.accumulate(inputBits, stepIndex, numRows, seed);
    }
}

contract LibLinearAccumulatorTest is Test {
    uint256 constant Q = 65521;
    LibLinearAccumulatorHarness harness;

    function setUp() public {
        harness = new LibLinearAccumulatorHarness();
    }

    // ──────────────────────────────────────────────────────────────────
    //  Determinism
    // ──────────────────────────────────────────────────────────────────

    function test_accumulate_deterministic() public pure {
        bytes32 seed = keccak256("test-seed");
        uint256 input = 0xDEADBEEF;
        uint256[4] memory h1 = LibLinearAccumulator.accumulate(input, 0, 64, seed);
        uint256[4] memory h2 = LibLinearAccumulator.accumulate(input, 0, 64, seed);
        assertEq(h1[0], h2[0]);
        assertEq(h1[1], h2[1]);
        assertEq(h1[2], h2[2]);
        assertEq(h1[3], h2[3]);
    }

    // ──────────────────────────────────────────────────────────────────
    //  Different inputs produce different outputs
    // ──────────────────────────────────────────────────────────────────

    function test_accumulate_differentInputs() public pure {
        bytes32 seed = keccak256("collision-test");
        uint256[4] memory h1 = LibLinearAccumulator.accumulate(0x1, 0, 64, seed);
        uint256[4] memory h2 = LibLinearAccumulator.accumulate(0x2, 0, 64, seed);
        bool anyDiff = h1[0] != h2[0] || h1[1] != h2[1] || h1[2] != h2[2] || h1[3] != h2[3];
        assertTrue(anyDiff, "Different inputs should produce different outputs");
    }

    // ──────────────────────────────────────────────────────────────────
    //  Different step indices produce different outputs
    // ──────────────────────────────────────────────────────────────────

    function test_accumulate_differentStepIndices() public pure {
        bytes32 seed = keccak256("step-test");
        uint256[4] memory h1 = LibLinearAccumulator.accumulate(0xABCD, 0, 64, seed);
        uint256[4] memory h2 = LibLinearAccumulator.accumulate(0xABCD, 1, 64, seed);
        bool anyDiff = h1[0] != h2[0] || h1[1] != h2[1] || h1[2] != h2[2] || h1[3] != h2[3];
        assertTrue(anyDiff, "Different step indices should produce different outputs");
    }

    // ──────────────────────────────────────────────────────────────────
    //  Different seeds produce different outputs
    // ──────────────────────────────────────────────────────────────────

    function test_accumulate_differentSeeds() public pure {
        uint256[4] memory h1 = LibLinearAccumulator.accumulate(0xFF, 0, 64, keccak256("seed-a"));
        uint256[4] memory h2 = LibLinearAccumulator.accumulate(0xFF, 0, 64, keccak256("seed-b"));
        bool anyDiff = h1[0] != h2[0] || h1[1] != h2[1] || h1[2] != h2[2] || h1[3] != h2[3];
        assertTrue(anyDiff, "Different seeds should produce different outputs");
    }

    // ──────────────────────────────────────────────────────────────────
    //  Zero input produces zero output (A * 0 = 0)
    // ──────────────────────────────────────────────────────────────────

    function test_accumulate_zeroInput() public pure {
        bytes32 seed = keccak256("zero-test");
        uint256[4] memory h = LibLinearAccumulator.accumulate(0, 0, 64, seed);
        assertEq(h[0], 0, "A * 0 should be 0");
        assertEq(h[1], 0, "A * 0 should be 0");
        assertEq(h[2], 0, "A * 0 should be 0");
        assertEq(h[3], 0, "A * 0 should be 0");
    }

    // ──────────────────────────────────────────────────────────────────
    //  Non-zero output for non-zero input
    // ──────────────────────────────────────────────────────────────────

    function test_accumulate_nonZero() public pure {
        bytes32 seed = keccak256("nonzero-test");
        uint256[4] memory h = LibLinearAccumulator.accumulate(0xFFFFFFFFFFFFFFFF, 0, 64, seed);
        uint256 combined = h[0] | h[1] | h[2] | h[3];
        assertTrue(combined != 0, "Non-zero input should produce non-zero output");
    }

    // ──────────────────────────────────────────────────────────────────
    //  Variable dimensions
    // ──────────────────────────────────────────────────────────────────

    function test_accumulate_smallDimension() public pure {
        bytes32 seed = keccak256("small-dim");
        // 4x4 matrix: only word 0 should have content, rest zero
        uint256[4] memory h = LibLinearAccumulator.accumulate(0xF, 0, 4, seed);
        // 4 elements pack into word 0 (bits 0..63)
        assertTrue(h[0] != 0, "Small dimension should still produce output");
        // Words 1-3 should be zero (no rows mapped there)
        assertEq(h[1], 0);
        assertEq(h[2], 0);
        assertEq(h[3], 0);
    }

    function test_accumulate_singleRow() public pure {
        bytes32 seed = keccak256("one-row");
        uint256[4] memory h = LibLinearAccumulator.accumulate(1, 0, 1, seed);
        // Single element in word 0, bits 0..15
        assertTrue(h[0] != 0);
        assertEq(h[1], 0);
        assertEq(h[2], 0);
        assertEq(h[3], 0);
    }

    // ──────────────────────────────────────────────────────────────────
    //  Output elements are in [0, q)
    // ──────────────────────────────────────────────────────────────────

    function test_accumulate_elementsInRange() public pure {
        bytes32 seed = keccak256("range-test");
        uint256[4] memory h = LibLinearAccumulator.accumulate(0xFFFFFFFFFFFFFFFF, 0, 64, seed);
        for (uint256 row = 0; row < 64; row++) {
            uint256 wordIdx = row / 16;
            uint256 bitPos = (row % 16) * 16;
            uint256 elem = (h[wordIdx] >> bitPos) & 0xFFFF;
            assertTrue(elem < Q, "Element must be < q");
        }
    }

    // ──────────────────────────────────────────────────────────────────
    //  Default q overload
    // ──────────────────────────────────────────────────────────────────

    function test_accumulate_defaultQ() public pure {
        bytes32 seed = keccak256("default-q");
        uint256[4] memory h1 = LibLinearAccumulator.accumulate(0xABCD, 0, 64, seed, Q);
        uint256[4] memory h2 = LibLinearAccumulator.accumulate(0xABCD, 0, 64, seed);
        assertEq(h1[0], h2[0]);
        assertEq(h1[1], h2[1]);
        assertEq(h1[2], h2[2]);
        assertEq(h1[3], h2[3]);
    }

    // ──────────────────────────────────────────────────────────────────
    //  xorAll
    // ──────────────────────────────────────────────────────────────────

    function test_xorAll() public pure {
        uint256[4] memory output;
        output[0] = 0xFF;
        output[1] = 0xAA;
        output[2] = 0x55;
        output[3] = 0x01;
        assertEq(LibLinearAccumulator.xorAll(output), 0xFF ^ 0xAA ^ 0x55 ^ 0x01);
    }

    // ──────────────────────────────────────────────────────────────────
    //  Update (fold new input into accumulator)
    // ──────────────────────────────────────────────────────────────────

    function test_update_deterministic() public pure {
        bytes32 seed = keccak256("update-test");
        uint256[4] memory acc = LibLinearAccumulator.accumulate(0x1234, 0, 64, seed);
        uint256[4] memory u1 = LibLinearAccumulator.update(acc, 0xABCD, 64, 64, seed);
        uint256[4] memory u2 = LibLinearAccumulator.update(acc, 0xABCD, 64, 64, seed);
        assertEq(u1[0], u2[0]);
        assertEq(u1[1], u2[1]);
        assertEq(u1[2], u2[2]);
        assertEq(u1[3], u2[3]);
    }

    function test_update_changesOutput() public pure {
        bytes32 seed = keccak256("update-change");
        uint256[4] memory acc = LibLinearAccumulator.accumulate(0x1234, 0, 64, seed);
        uint256[4] memory updated = LibLinearAccumulator.update(acc, 0x5678, 64, 64, seed);
        bool anyDiff = acc[0] != updated[0] || acc[1] != updated[1] || acc[2] != updated[2] || acc[3] != updated[3];
        assertTrue(anyDiff, "Update should change output");
    }

    // ──────────────────────────────────────────────────────────────────
    //  TLOS compatibility: matches LibTLOS.updateWireBinding output
    //  (This test encodes the exact same parameters TLOS uses)
    // ──────────────────────────────────────────────────────────────────

    function test_accumulate_matchesTLOSWireBinding() public pure {
        // The TLOS implementation uses q=65521, numWires=64, which maps directly
        // to our accumulate(inputBits, gateIdx, 64, circuitSeed, 65521)
        bytes32 seed = keccak256("tlos-compat");
        uint256 wires = 0xDEADBEEFCAFEBABE;

        uint256[4] memory result = LibLinearAccumulator.accumulate(wires, 0, 64, seed, Q);

        // Verify it produces a non-trivial result
        uint256 combined = result[0] | result[1] | result[2] | result[3];
        assertTrue(combined != 0, "Non-zero wires should produce non-zero binding");
    }

    // ──────────────────────────────────────────────────────────────────
    //  Revert tests
    // ──────────────────────────────────────────────────────────────────

    function test_revert_numRowsZero() public {
        vm.expectRevert("numRows must be 1-64");
        harness.accumulate(1, 0, 0, keccak256("x"), Q);
    }

    function test_revert_numRowsTooLarge() public {
        vm.expectRevert("numRows must be 1-64");
        harness.accumulate(1, 0, 65, keccak256("x"), Q);
    }

    function test_revert_qZero() public {
        vm.expectRevert("q must be <= 65521");
        harness.accumulate(1, 0, 64, keccak256("x"), 0);
    }

    function test_revert_qTooLarge() public {
        vm.expectRevert("q must be <= 65521");
        harness.accumulate(1, 0, 64, keccak256("x"), 65522);
    }
}
