// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";

import {MockRebasingLST} from "src/mocks/MockRebasingLST.sol";
import {MockNonRebasingLST} from "src/mocks/MockNonRebasingLST.sol";

contract MockLSTsTest is Test {
    function testMockRebasingLSTFlows() public {
        MockRebasingLST token = new MockRebasingLST("Mock stETH", "mstETH", 500);

        assertEq(token.index(), 1e18);

        token.mint(address(this), 100 ether);
        assertEq(token.balanceOf(address(this)), 100 ether);

        token.rebaseByBps(100);
        assertEq(token.index(), 1.01e18);

        token.setIndex(1.02e18);
        assertEq(token.index(), 1.02e18);

        // no-op branch
        token.setIndex(1.02e18);
        assertEq(token.index(), 1.02e18);

        assertEq(token.previewSharesForAmount(1 ether), 1 ether);
        assertEq(token.previewAmountForShares(2 ether), 2 ether);
        assertEq(token.totalShares(), token.totalSupply());
        assertEq(token.sharesOf(address(this)), token.balanceOf(address(this)));
    }

    function testMockRebasingLSTReverts() public {
        MockRebasingLST token = new MockRebasingLST("Mock stETH", "mstETH", 100);

        vm.expectRevert();
        token.setIndex(0);

        token.setIndex(1e18);

        vm.expectRevert();
        token.setIndex(0.99e18);

        vm.expectRevert();
        token.rebaseByBps(200);

        vm.prank(address(0xBEEF));
        vm.expectRevert();
        token.mint(address(0xCAFE), 1 ether);

        vm.prank(address(0xBEEF));
        vm.expectRevert();
        token.setIndex(1.01e18);

        vm.prank(address(0xBEEF));
        vm.expectRevert();
        token.rebaseByBps(50);
    }

    function testMockNonRebasingLSTFlows() public {
        MockNonRebasingLST token = new MockNonRebasingLST("Mock rETH", "mrETH");
        token.mint(address(this), 100 ether);
        assertEq(token.balanceOf(address(this)), 100 ether);

        token.setExchangeRateWad(1.05e18);
        assertEq(token.exchangeRateWad(), 1.05e18);
    }

    function testMockNonRebasingLSTOwnerChecks() public {
        MockNonRebasingLST token = new MockNonRebasingLST("Mock rETH", "mrETH");

        vm.prank(address(0xBEEF));
        vm.expectRevert();
        token.mint(address(0xBEEF), 1 ether);

        vm.prank(address(0xBEEF));
        vm.expectRevert();
        token.setExchangeRateWad(2e18);
    }
}
