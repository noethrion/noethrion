// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

// 05 · Finalize a submitted batch after the challenge window.
//
// On a real testnet you would simply wait the configured challenge window
// (default 1 hour for the lifecycle example). On a local Anvil node you can
// fast-forward time with vm.warp, which this script does automatically.
//
// Reads:
//   $ATTESTER   — deployed NoethrionAttester
//   $EPOCH      — batch epoch
//   $WARP       — "1" to fast-forward time past the challenge window (Anvil only)
//   $PRIVATE_KEY — any account (no role required)
//
// Run (via `cast` — see the note in 04_propose_batch.s.sol; the $WARP
// fast-forward becomes an explicit evm_increaseTime RPC call, Anvil only):
//   export ATTESTER=0x...
//   export EPOCH=1
//   export PRIVATE_KEY=0xac0974...80c9
//   cast rpc evm_increaseTime 3700 --rpc-url http://localhost:8545
//   cast rpc evm_mine --rpc-url http://localhost:8545
//   cast send "$ATTESTER" "finalizeBatch(uint64)" "$EPOCH" \
//       --private-key "$PRIVATE_KEY" --rpc-url http://localhost:8545

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {NoethrionAttester} from "../../contracts/src/NoethrionAttester.sol";

contract FinalizeBatch is Script {
    function run() external {
        address attesterAddr = vm.envAddress("ATTESTER");
        uint64 epoch = uint64(vm.envUint("EPOCH"));
        uint256 pk = vm.envUint("PRIVATE_KEY");
        bool warp = vm.envOr("WARP", uint256(0)) != 0;

        NoethrionAttester attester = NoethrionAttester(attesterAddr);

        if (warp) {
            uint256 challengeWindow = attester.challengeWindow();
            // Re-fetch the batch timestamp.
            ( , , , uint64 batchTs, , , , ) = attester.batches(epoch);
            require(batchTs != 0, "epoch not proposed yet");
            uint256 unlocksAt = uint256(batchTs) + challengeWindow + 1;
            vm.warp(unlocksAt);
            console2.log("Warped chain time to", unlocksAt, "(challenge window cleared)");
        }

        vm.startBroadcast(pk);
        attester.finalizeBatch(epoch);
        vm.stopBroadcast();

        ( , , , , , bool finalized, , ) = attester.batches(epoch);
        console2.log("Epoch", epoch, "finalized:", finalized);
        console2.log("Next: claim individual leaves via 06_claim.s.sol");
    }
}
