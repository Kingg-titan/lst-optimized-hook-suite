// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";

import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {HookMiner} from "@uniswap/v4-periphery/src/utils/HookMiner.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";

import {AddressConstants} from "hookmate/constants/AddressConstants.sol";
import {V4PoolManagerDeployer} from "hookmate/artifacts/V4PoolManager.sol";

import {LSTOptimizedHook} from "src/LSTOptimizedHook.sol";
import {MockRebasingLST} from "src/mocks/MockRebasingLST.sol";
import {MockNonRebasingLST} from "src/mocks/MockNonRebasingLST.sol";
import {YieldDistributionController} from "src/modules/YieldDistributionController.sol";

contract DeployLSTSuite is Script {
    address internal constant CREATE2_DEPLOYER = 0x4e59b44847b379578588920cA78FbF26c0B4956C;

    function run() external {
        uint256 privateKey = vm.envOr("PRIVATE_KEY", uint256(0));
        if (privateKey == 0) {
            privateKey = vm.envUint("SEPOLIA_PRIVATE_KEY");
        }
        address deployer = vm.addr(privateKey);
        address owner = vm.envOr("OWNER_ADDRESS", deployer);

        address poolManagerAddress = vm.envOr("POOL_MANAGER_ADDRESS", address(0));
        if (poolManagerAddress == address(0)) {
            poolManagerAddress = vm.envOr("POOL_MANAGER", address(0));
        }
        if (poolManagerAddress == address(0)) {
            poolManagerAddress = block.chainid == 31337
                ? V4PoolManagerDeployer.deploy(address(0x4444))
                : AddressConstants.getPoolManagerAddress(block.chainid);
        }

        vm.startBroadcast(privateKey);

        YieldDistributionController controller = new YieldDistributionController(owner);
        MockRebasingLST rebasing = new MockRebasingLST("Mock stETH", "mstETH", 2_000);
        MockNonRebasingLST nonRebasing = new MockNonRebasingLST("Mock rETH", "mrETH");

        uint160 flags = Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG;
        bytes memory constructorArgs = abi.encode(IPoolManager(poolManagerAddress), controller);
        (address expectedAddress, bytes32 salt) =
            HookMiner.find(CREATE2_DEPLOYER, flags, type(LSTOptimizedHook).creationCode, constructorArgs);

        LSTOptimizedHook hook = new LSTOptimizedHook{salt: salt}(IPoolManager(poolManagerAddress), controller);
        require(address(hook) == expectedAddress, "hook address mismatch");

        controller.setHook(address(hook));

        bool mintDemoSupply = vm.envOr("MINT_DEMO_SUPPLY", block.chainid == 31337);
        if (mintDemoSupply) {
            rebasing.mint(deployer, 1_000_000 ether);
            nonRebasing.mint(deployer, 1_000_000 ether);
        }

        vm.stopBroadcast();

        console2.log("chainId", block.chainid);
        console2.log("deployer", deployer);
        console2.log("owner", owner);
        console2.log("poolManager", poolManagerAddress);
        console2.log("controller", address(controller));
        console2.log("hook", address(hook));
        console2.log("mockRebasingLST", address(rebasing));
        console2.log("mockNonRebasingLST", address(nonRebasing));
    }
}
