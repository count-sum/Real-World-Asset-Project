// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ControlModule} from "./ControlModule.sol";
import {IAssetContract} from "./Interfaces/IAssetContract.sol";

contract ControlModule is AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    error ControlModule__UnauthorizedAsset();
    error ControlModule__UnauthorizedFactory();
    error ControlModule__AssetNotAuthorized();
    error ControlModule__RatioTooHigh();

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 public constant ASSET_MANAGER_ROLE = keccak256("ASSET_MANAGER_ROLE");
    uint256 public constant MAX_RATIO = 10000;

    mapping(address => bool) public authorizedAssets;
    mapping(address => bool) public authorizedFactories;

    event AssetAuthorized(address indexed asset, bool authorized);
    event FactoryAuthorized(address indexed factory, bool authorized);
    event AssetFrozen(address indexed asset, address indexed account);
    event AssetUnfrozen(address indexed asset, address indexed account);
    event AssetGloballyFrozen(address indexed asset);
    event AssetGloballyUnfrozen(address indexed asset);
    event CollateralRatioUpdated(address indexed asset, uint256 newRatio);

    modifier onlyAuthorizedAsset() {
        require(authorizedAssets[msg.sender], ControlModule__UnauthorizedAsset());
        _;
    }

    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
        _grantRole(OPERATOR_ROLE, msg.sender);
        _grantRole(ASSET_MANAGER_ROLE, msg.sender);
    }

    /**
     * @dev Authorize or deauthorize an asset contract
     */
    function setAssetAuthorization(address asset, bool authorized) external onlyRole(ADMIN_ROLE) {
        authorizedAssets[asset] = authorized;
        emit AssetAuthorized(asset, authorized);
    }

    /**
     * @dev Authorize or deauthorize a factory contract
     */
    function setFactoryAuthorization(address factory, bool authorized) external onlyRole(ADMIN_ROLE) {
        authorizedFactories[factory] = authorized;
        emit FactoryAuthorized(factory, authorized);
    }

    /**
     * @dev Freeze a specific address for an asset
     */
    function freezeAddressForAsset(address asset, address account) external onlyRole(OPERATOR_ROLE) {
        require(authorizedAssets[asset], ControlModule__AssetNotAuthorized());
        IAssetContract(asset).freezeAddress(account);
        emit AssetFrozen(asset, account);
    }

    /**
     * @dev Unfreeze a specific address for an asset
     */
    function unfreezeAddressForAsset(address asset, address account) external onlyRole(OPERATOR_ROLE) {
        require(authorizedAssets[asset], ControlModule__AssetNotAuthorized());
        IAssetContract(asset).unfreezeAddress(account);
        emit AssetUnfrozen(asset, account);
    }

    /**
     * @dev Freeze entire asset
     */
    function freezeAsset(address asset) external onlyRole(OPERATOR_ROLE) {
        require(authorizedAssets[asset], ControlModule__AssetNotAuthorized());
        IAssetContract(asset).freezeAsset();
        emit AssetGloballyFrozen(asset);
    }

    /**
     * @dev Unfreeze entire asset
     */
    function unfreezeAsset(address asset) external onlyRole(OPERATOR_ROLE) {
        require(authorizedAssets[asset], ControlModule__AssetNotAuthorized());
        IAssetContract(asset).unfreezeAsset();
        emit AssetGloballyUnfrozen(asset);
    }

    /**
     * @dev Update collateral ratio for an asset
     */
    function updateAssetCollateralRatio(address asset, uint256 newRatio) external onlyRole(ASSET_MANAGER_ROLE) {
        require(authorizedAssets[asset], ControlModule__AssetNotAuthorized());
        require(newRatio <= MAX_RATIO, ControlModule__RatioTooHigh());
        IAssetContract(asset).updateCollateralRatio(newRatio);
        emit CollateralRatioUpdated(asset, newRatio);
    }

    /**
     * @dev Register a new asset (called by factory)
     */
    function registerAsset(address asset) external {
        require(authorizedFactories[msg.sender], ControlModule__UnauthorizedFactory());
        authorizedAssets[asset] = true;
        emit AssetAuthorized(asset, true);
    }
}
