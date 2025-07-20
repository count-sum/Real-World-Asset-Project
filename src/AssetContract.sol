// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ControlModule} from "./ControlModule.sol";

contract AssetContract is AccessControl, ReentrancyGuard, Pausable, Initializable {
    using SafeERC20 for IERC20;

    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant REBALANCER_ROLE = keccak256("REBALANCER_ROLE");
    uint256 public constant MAX_RATIO = 10000;

    struct AssetInfo {
        string name;
        string symbol;
        address underlyingToken;
        uint256 totalSupply;
        uint256 collateralRatio; // Basis points (10000 = 100%)
    }

    struct CollateralInfo {
        uint256 onChainAmount;
        uint256 offChainAmount;
        uint256 lastUpdateTimestamp;
    }

    AssetInfo public assetInfo;
    CollateralInfo public collateralInfo;
    ControlModule public controlModule;

    mapping(address => uint256) public balances;
    mapping(address => bool) public frozenAddresses;
    mapping(address => IERC4626) public authorizedVaults;

    bool public assetFrozen;

    event Mint(address indexed to, uint256 amount, uint256 onChainCollateral, uint256 offChainCollateral);
    event Burn(address indexed from, uint256 amount);
    event Rebalance(uint256 newOnChainAmount, uint256 newOffChainAmount, uint256 timestamp);
    event VaultDeposit(address indexed vault, uint256 amount, uint256 sharesMinted);
    event VaultWithdraw(address indexed vault, uint256 amount, uint256 sharesWithdrawn);
    event AddressFrozen(address indexed account);
    event AddressUnfrozen(address indexed account);
    event AssetFrozen();
    event AssetUnfrozen();
    event CollateralRatioUpdated(uint256 oldRatio, uint256 newRatio);

    error AssetContract__OnlyControlModule();
    error AssetContract__AddressFrozen();
    error AssetContract__AssetFrozen();
    error AssetContract__InvalidAmount();
    error AssetContract__InsufficientBalance();
    error AssetContract__VaultNotAuthorized();
    error AssetContract__InvalidVault();
    error AssetContract__InvalidControlModule();
    error AssetContract__InvalidAdmin();
    error AssetContract__InvalidRatio();
    error AssetContract__ZeroSharesMinted();
    error AssetContract__ZeroSharesWithdrawn();

    modifier onlyControlModule() {
        require(msg.sender == address(controlModule), AssetContract__OnlyControlModule());
        _;
    }

    modifier notFrozen(address account) {
        require(!frozenAddresses[account], AssetContract__AddressFrozen());
        require(!assetFrozen, AssetContract__AssetFrozen());
        _;
    }

    modifier whenNotAssetFrozen() {
        require(!assetFrozen, AssetContract__AssetFrozen());
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev Initialize the asset contract
     * @notice Called by factory
     */
    function initialize(
        string memory _name,
        string memory _symbol,
        address _underlyingToken,
        uint256 _initialCollateralRatio,
        address _controlModule,
        address _admin
    ) external {
        require(_controlModule != address(0), AssetContract__InvalidControlModule());
        require(_admin != address(0), AssetContract__InvalidAdmin());

        assetInfo = AssetInfo({
            name: _name,
            symbol: _symbol,
            underlyingToken: _underlyingToken,
            totalSupply: 0,
            collateralRatio: _initialCollateralRatio
        });

        controlModule = ControlModule(_controlModule);

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(MINTER_ROLE, _admin);
        _grantRole(REBALANCER_ROLE, _admin);
    }

    /**
     * @dev Mint new asset tokens
     */
    function mint(address to, uint256 amount, uint256 onChainCollateral, uint256 offChainCollateral)
        external
        nonReentrant
        onlyRole(MINTER_ROLE)
        notFrozen(to)
    {
        require(amount > 0, AssetContract__InvalidAmount());

        // Update collateral info
        collateralInfo.onChainAmount += onChainCollateral;
        collateralInfo.offChainAmount += offChainCollateral;
        collateralInfo.lastUpdateTimestamp = block.timestamp;

        // Mint tokens
        balances[to] += amount;
        assetInfo.totalSupply += amount;

        // Transfer on-chain collateral
        if (onChainCollateral > 0) {
            IERC20(assetInfo.underlyingToken).safeTransferFrom(msg.sender, address(this), onChainCollateral);
        }

        emit Mint(to, amount, onChainCollateral, offChainCollateral);
    }

    /**
     * @dev Burn asset tokens
     */
    function burn(address from, uint256 amount) external nonReentrant onlyRole(MINTER_ROLE) notFrozen(from) {
        require(balances[from] >= amount, AssetContract__InsufficientBalance());

        balances[from] -= amount;
        assetInfo.totalSupply -= amount;

        emit Burn(from, amount);
    }

    /**
     * @dev Rebalance collateral between on-chain and off-chain
     */
    function rebalance(uint256 newOnChainAmount, uint256 newOffChainAmount)
        external
        nonReentrant
        onlyRole(REBALANCER_ROLE)
        whenNotAssetFrozen
    {
        uint256 currentOnChain = collateralInfo.onChainAmount;

        // Handle on-chain collateral changes
        if (newOnChainAmount > currentOnChain) {
            // Need to deposit more on-chain collateral
            uint256 depositAmount = newOnChainAmount - currentOnChain;
            IERC20(assetInfo.underlyingToken).safeTransferFrom(msg.sender, address(this), depositAmount);
        } else if (newOnChainAmount < currentOnChain) {
            // Need to withdraw on-chain collateral
            uint256 withdrawAmount = currentOnChain - newOnChainAmount;
            IERC20(assetInfo.underlyingToken).safeTransfer(msg.sender, withdrawAmount);
        }

        // Update collateral info
        collateralInfo.onChainAmount = newOnChainAmount;
        collateralInfo.offChainAmount = newOffChainAmount;
        collateralInfo.lastUpdateTimestamp = block.timestamp;

        emit Rebalance(newOnChainAmount, newOffChainAmount, block.timestamp);
    }

    /**
     * @dev Deposit into ERC-4626 vault
     */
    function depositToVault(address vault, uint256 amount)
        external
        nonReentrant
        onlyRole(REBALANCER_ROLE)
        whenNotAssetFrozen
    {
        require(address(authorizedVaults[vault]) != address(0), AssetContract__VaultNotAuthorized());

        IERC20(assetInfo.underlyingToken).safeIncreaseAllowance(vault, amount);
        uint256 sharesMinted = IERC4626(vault).deposit(amount, address(this));
        require(sharesMinted > 0, AssetContract__ZeroSharesMinted());

        emit VaultDeposit(vault, amount, sharesMinted);
    }

    /**
     * @dev Withdraw from ERC-4626 vault
     */
    function withdrawFromVault(address vault, uint256 amount)
        external
        nonReentrant
        onlyRole(REBALANCER_ROLE)
        whenNotAssetFrozen
    {
        require(address(authorizedVaults[vault]) != address(0), AssetContract__VaultNotAuthorized());

        uint256 sharesWithdrawn = IERC4626(vault).withdraw(amount, address(this), address(this));
        require(sharesWithdrawn > 0, AssetContract__ZeroSharesWithdrawn());

        emit VaultWithdraw(vault, amount, sharesWithdrawn);
    }

    /**
     * @dev Authorize a vault for deposits/withdrawals
     */
    function authorizeVault(address vault) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(vault != address(0), AssetContract__InvalidVault());
        authorizedVaults[vault] = IERC4626(vault);
    }

    /**
     * @dev Deauthorize a vault
     */
    function deauthorizeVault(address vault) external onlyRole(DEFAULT_ADMIN_ROLE) {
        delete authorizedVaults[vault];
    }

    // Control module functions
    function freezeAddress(address account) external onlyControlModule {
        frozenAddresses[account] = true;
        emit AddressFrozen(account);
    }

    function unfreezeAddress(address account) external onlyControlModule {
        frozenAddresses[account] = false;
        emit AddressUnfrozen(account);
    }

    function freezeAsset() external onlyControlModule {
        assetFrozen = true;
        emit AssetFrozen();
    }

    function unfreezeAsset() external onlyControlModule {
        assetFrozen = false;
        emit AssetUnfrozen();
    }

    function updateCollateralRatio(uint256 newRatio) external onlyControlModule {
        require(newRatio <= MAX_RATIO, AssetContract__InvalidRatio());
        uint256 oldRatio = assetInfo.collateralRatio;
        assetInfo.collateralRatio = newRatio;
        emit CollateralRatioUpdated(oldRatio, newRatio);
    }

    // View functions
    function balanceOf(address account) external view returns (uint256) {
        return balances[account];
    }

    function totalSupply() external view returns (uint256) {
        return assetInfo.totalSupply;
    }

    function getCollateralInfo() external view returns (CollateralInfo memory) {
        return collateralInfo;
    }

    function getAssetInfo() external view returns (AssetInfo memory) {
        return assetInfo;
    }
}
