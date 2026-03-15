// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface IRebasingIndexToken {
    function index() external view returns (uint256);
    function totalShares() external view returns (uint256);
    function sharesOf(address account) external view returns (uint256);
    function previewSharesForAmount(uint256 amount) external view returns (uint256);
    function previewAmountForShares(uint256 shares) external view returns (uint256);
}
