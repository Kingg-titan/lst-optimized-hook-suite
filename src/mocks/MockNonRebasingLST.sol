// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockNonRebasingLST is ERC20 {
    address public immutable owner;
    uint256 public exchangeRateWad;

    error NotOwner();

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) {
        owner = msg.sender;
        exchangeRateWad = 1e18;
    }

    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }

    function setExchangeRateWad(uint256 nextRateWad) external onlyOwner {
        exchangeRateWad = nextRateWad;
    }
}
