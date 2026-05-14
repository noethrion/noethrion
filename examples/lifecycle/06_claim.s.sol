// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

// 06 · Claim NOET against a finalized batch.
//
// Reads:
//   $ATTESTER   — deployed NoethrionAttester
//   $TOKEN      — deployed NoethrionToken (so the script can log balance after)
//   $EPOCH      — batch epoch
//   $BENEFICIARY— address minted to (one of the leaves in batch.json)
//   $AMOUNT     — uint128 wei-scale NOET (matching the leaf encoding)
//   $PROOF      — comma-separated hex siblings, e.g. "0xabc...,0xdef..."
//   $PRIVATE_KEY — any account (claim is permissionless)
//
// Run:
//   export ATTESTER=0x...
//   export TOKEN=0x...
//   export EPOCH=1
//   export BENEFICIARY=0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
//   export AMOUNT=100000000000000000000   # 100 NOET in 18-decimal wei
//   export PROOF=0xabc...,0xdef...        # from batch.json -> leaves[i].proof
//   export PRIVATE_KEY=0xac0974...80c9
//   forge script examples/lifecycle/06_claim.s.sol \
//       --rpc-url http://localhost:8545 --broadcast

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {NoethrionAttester} from "../../contracts/src/NoethrionAttester.sol";

interface IERC20Min {
    function balanceOf(address) external view returns (uint256);
}

contract Claim is Script {
    function run() external {
        address attesterAddr = vm.envAddress("ATTESTER");
        address tokenAddr = vm.envAddress("TOKEN");
        uint64 epoch = uint64(vm.envUint("EPOCH"));
        address beneficiary = vm.envAddress("BENEFICIARY");
        uint128 amount = uint128(vm.envUint("AMOUNT"));
        bytes32[] memory proof = vm.envBytes32("PROOF", ",");
        uint256 pk = vm.envUint("PRIVATE_KEY");

        NoethrionAttester attester = NoethrionAttester(attesterAddr);

        uint256 balBefore = IERC20Min(tokenAddr).balanceOf(beneficiary);

        vm.startBroadcast(pk);
        attester.claim(epoch, proof, beneficiary, amount);
        vm.stopBroadcast();

        uint256 balAfter = IERC20Min(tokenAddr).balanceOf(beneficiary);

        console2.log("Claim succeeded");
        console2.log("  beneficiary :", beneficiary);
        console2.log("  amount (wei):", amount);
        console2.log("  bal before  :", balBefore);
        console2.log("  bal after   :", balAfter);
        console2.log("Next: 07_verify_offchain.sh - independent off-chain verification");
    }
}
