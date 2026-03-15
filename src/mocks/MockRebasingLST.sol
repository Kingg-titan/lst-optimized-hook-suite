// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockRebasingLST is ERC20 {
    error NotOwner();
    error InvalidIndex();
    error RebaseTooLarge(uint256 deltaBps, uint256 maxDeltaBps);

    event Rebased(uint256 previousIndex, uint256 nextIndex);

    uint256 public constant SCALE = 1e18;

    address public immutable owner;
    uint256 public immutable maxRebaseDeltaBps;

    uint256 private _index;

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    constructor(string memory name_, string memory symbol_, uint256 maxRebaseDeltaBps_) ERC20(name_, symbol_) {
        owner = msg.sender;
        _index = SCALE;
        maxRebaseDeltaBps = maxRebaseDeltaBps_;
    }

    function index() external view returns (uint256) {
        return _index;
    }

    // Exposed for compatibility with the rebasing-interface shape.
    function totalShares() external view returns (uint256) {
        return totalSupply();
    }

    function sharesOf(address account) external view returns (uint256) {
        return balanceOf(account);
    }

    function previewSharesForAmount(uint256 amount) external pure returns (uint256) {
        return amount;
    }

    function previewAmountForShares(uint256 shares) external pure returns (uint256) {
        return shares;
    }

    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }

    function rebaseByBps(uint16 deltaBps) external onlyOwner {
        uint256 nextIndex = _index + ((_index * deltaBps) / 10_000);
        _setIndex(nextIndex);
    }

    function setIndex(uint256 nextIndex) external onlyOwner {
        _setIndex(nextIndex);
    }

    function _setIndex(uint256 nextIndex) internal {
        if (nextIndex < _index || nextIndex == 0) revert InvalidIndex();
        if (nextIndex == _index) return;

        uint256 deltaBps = ((nextIndex - _index) * 10_000) / _index;
        if (maxRebaseDeltaBps > 0 && deltaBps > maxRebaseDeltaBps) {
            revert RebaseTooLarge(deltaBps, maxRebaseDeltaBps);
        }

        uint256 previous = _index;
        _index = nextIndex;
        emit Rebased(previous, nextIndex);
    }
}
