// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {ControlModule} from "./ControlModule.sol";
import {AssetContract} from "./AssetContract.sol";

contract AssetFactory is AccessControl, ReentrancyGuard {
    using Clones for address;

    bytes32 public constant ASSET_CREATOR_ROLE = keccak256("ASSET_CREATOR_ROLE");

    address public immutable assetImplementation;
    ControlModule public immutable controlModule;

    mapping(address => bool) public deployedAssets;
    address[] public totalAssets;

    uint256 public constant MAX_RATIO = 10000;

    event AssetCreated(
        address indexed asset,
        string name,
        string symbol,
        address underlyingToken,
        uint256 collateralRatio,
        address indexed creator
    );

    error AssetFactory__InvalidControlModule();
    error AssetFactory__InvalidName();
    error AssetFactory__InvalidSymbol();
    error AssetFactory__InvalidUnderlyingToken();
    error AssetFactory__InvalidCollateralRatio();
    error AssetFactory__InvalidAdmin();
    error AssetFactory__IndexOutOfBounds();

    constructor(address _controlModule) {
        require(_controlModule != address(0), AssetFactory__InvalidControlModule());

        controlModule = ControlModule(_controlModule);
        assetImplementation = address(new AssetContract());

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ASSET_CREATOR_ROLE, msg.sender);
    }

    /**
     * @dev Create a new asset contract
     */
    function createAsset(
        string memory name,
        string memory symbol,
        address underlyingToken,
        uint256 initialCollateralRatio,
        address admin
    ) external nonReentrant onlyRole(ASSET_CREATOR_ROLE) returns (address) {
        require(bytes(name).length > 0, AssetFactory__InvalidName());
        require(bytes(symbol).length > 0, AssetFactory__InvalidSymbol());
        require(underlyingToken != address(0), AssetFactory__InvalidUnderlyingToken());
        require(initialCollateralRatio <= MAX_RATIO, AssetFactory__InvalidCollateralRatio());
        require(admin != address(0), AssetFactory__InvalidAdmin());

        // Clone the implementation
        address asset = assetImplementation.clone();

        // Initialize the asset
        AssetContract(asset).initialize(
            name, symbol, underlyingToken, initialCollateralRatio, address(controlModule), admin
        );

        // Register with control module
        controlModule.registerAsset(asset);

        // Track deployed assets
        deployedAssets[asset] = true;
        totalAssets.push(asset);

        emit AssetCreated(asset, name, symbol, underlyingToken, initialCollateralRatio, msg.sender);

        return asset;
    }

    /**
     * @dev Get the number of deployed assets
     */
    function getAssetCount() external view returns (uint256) {
        return totalAssets.length;
    }

    /**
     * @dev Get asset at index
     */
    function getAssetAt(uint256 index) external view returns (address) {
        require(index < totalAssets.length, AssetFactory__IndexOutOfBounds());
        return totalAssets[index];
    }

    /**
     * @dev Check if an asset was deployed by this factory
     */
    function isDeployedAsset(address asset) external view returns (bool) {
        return deployedAssets[asset];
    }
}
