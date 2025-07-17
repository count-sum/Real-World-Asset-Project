// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IAssetContract {
    function freezeAddress(address account) external;
    function unfreezeAddress(address account) external;
    function freezeAsset() external;
    function unfreezeAsset() external;
    function updateCollateralRatio(uint256 newRatio) external;
    function controlModule() external view returns (address);
}
