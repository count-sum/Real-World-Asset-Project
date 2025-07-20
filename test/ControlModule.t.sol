// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {ControlModule} from "../src/ControlModule.sol";
import {AssetContract} from "../src/AssetContract.sol";
import {AssetFactory} from "../src/AssetFactory.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract ERC20Mock is ERC20 {
    constructor() ERC20("Mock", "MOCK") {
        _mint(msg.sender, 1_000_000 ether);
    }
}

contract ERC4626Mock is IERC4626, Test {
    mapping(address => uint256) public balances;
    mapping(address => mapping(address => uint256)) public allowances;
    uint256 public totalAssets_;
    uint256 public totalSupply_;

    function deposit(uint256 assets, address receiver) external returns (uint256 shares) {
        balances[receiver] += assets;
        totalAssets_ += assets;
        totalSupply_ += assets;
        return assets;
    }

    function withdraw(uint256 assets, address receiver, address owner) external returns (uint256 shares) {
        require(balances[owner] >= assets, "Insufficient owner shares");
        balances[owner] -= assets;
        totalAssets_ -= assets;
        totalSupply_ -= assets;
        return assets;
    }

    function mint(uint256 shares, address receiver) external returns (uint256 assets) {
        balances[receiver] += shares;
        totalAssets_ += shares;
        totalSupply_ += shares;
        return shares;
    }

    function redeem(uint256 shares, address receiver, address owner) external returns (uint256 assets) {
        require(balances[owner] >= shares, "Insufficient owner shares");
        balances[owner] -= shares;
        totalAssets_ -= shares;
        totalSupply_ -= shares;
        return shares;
    }

    // ERC20 functions
    function balanceOf(address account) external view returns (uint256) {
        return balances[account];
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        balances[msg.sender] -= amount;
        balances[to] += amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        allowances[from][msg.sender] -= amount;
        balances[from] -= amount;
        balances[to] += amount;
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowances[msg.sender][spender] = amount;
        return true;
    }

    function allowance(address owner, address spender) external view returns (uint256) {
        return allowances[owner][spender];
    }

    function name() external pure returns (string memory) {
        return "Mock Vault";
    }

    function symbol() external pure returns (string memory) {
        return "MVAULT";
    }

    function decimals() external pure returns (uint8) {
        return 18;
    }

    // ERC4626 functions
    function totalAssets() external view returns (uint256) {
        return totalAssets_;
    }

    function totalSupply() external view returns (uint256) {
        return totalSupply_;
    }

    function convertToShares(uint256 assets) external pure returns (uint256 shares) {
        return assets;
    }

    function convertToAssets(uint256 shares) external pure returns (uint256 assets) {
        return shares;
    }

    function maxDeposit(address) external pure returns (uint256) {
        return type(uint256).max;
    }

    function maxMint(address) external pure returns (uint256) {
        return type(uint256).max;
    }

    function maxWithdraw(address) external pure returns (uint256) {
        return type(uint256).max;
    }

    function maxRedeem(address) external pure returns (uint256) {
        return type(uint256).max;
    }

    function asset() external pure returns (address) {
        return address(0);
    }

    function previewDeposit(uint256 assets) external pure returns (uint256 shares) {
        return assets;
    }

    function previewMint(uint256 shares) external pure returns (uint256 assets) {
        return shares;
    }

    function previewWithdraw(uint256 assets) external pure returns (uint256 shares) {
        return assets;
    }

    function previewRedeem(uint256 shares) external pure returns (uint256 assets) {
        return shares;
    }
}

contract ControlModuleTest is Test {
    ControlModule controlModule;
    AssetFactory assetFactory;
    AssetContract asset;

    ERC20Mock underlying;
    ERC4626Mock vault;

    address admin = address(0xABCD);
    address operator = address(0xBEEF);
    address assetManager = address(0xC0DE);
    address factory = address(0xDEAD);
    address user = address(0xAAAA);

    // Events for testing
    event AssetAuthorized(address indexed asset, bool authorized);
    event FactoryAuthorized(address indexed factory, bool authorized);
    event AssetFrozen(address indexed asset, address indexed user);
    event AssetGloballyFrozen(address indexed asset);
    event AssetGloballyUnfrozen(address indexed asset);

    function setUp() public {
        controlModule = new ControlModule();

        controlModule.grantRole(controlModule.ADMIN_ROLE(), admin);
        controlModule.grantRole(controlModule.OPERATOR_ROLE(), operator);
        controlModule.grantRole(controlModule.ASSET_MANAGER_ROLE(), assetManager);

        assetFactory = new AssetFactory(address(controlModule));

        assetFactory.grantRole(assetFactory.ASSET_CREATOR_ROLE(), admin);

        vm.prank(admin);
        controlModule.setFactoryAuthorization(address(assetFactory), true);

        assetFactory.grantRole(assetFactory.ASSET_CREATOR_ROLE(), factory);

        underlying = new ERC20Mock();
        underlying.transfer(user, 1000 ether);
        underlying.transfer(admin, 500 ether);

        vault = new ERC4626Mock();

        vm.prank(factory);
        address deployedAssetAddr = assetFactory.createAsset("TestAsset", "TST", address(underlying), 8000, admin);
        asset = AssetContract(deployedAssetAddr);

        vm.prank(admin);
        controlModule.setAssetAuthorization(address(asset), true);

        vm.prank(admin);
        asset.authorizeVault(address(vault));

        underlying.transfer(address(asset), 100 ether);
    }

    function testSetAssetAuthorization() public {
        vm.prank(user);
        vm.expectRevert(
            "AccessControl: account 0x000000000000000000000000000000000000aaaa is missing role 0xa49807205ce4d355092ef5a8a18f56e8913cf4a201fbe287825b095693c21775"
        );
        controlModule.setAssetAuthorization(address(asset), false);

        vm.prank(admin);
        controlModule.setAssetAuthorization(address(asset), false);
        assertFalse(controlModule.authorizedAssets(address(asset)));

        vm.expectEmit(true, false, false, true);
        emit AssetAuthorized(address(asset), true);
        vm.prank(admin);
        controlModule.setAssetAuthorization(address(asset), true);
    }

    function testSetFactoryAuthorization() public {
        vm.prank(user);
        vm.expectRevert(
            "AccessControl: account 0x000000000000000000000000000000000000aaaa is missing role 0xa49807205ce4d355092ef5a8a18f56e8913cf4a201fbe287825b095693c21775"
        );
        controlModule.setFactoryAuthorization(factory, false);

        vm.prank(admin);
        controlModule.setFactoryAuthorization(factory, false);
        assertFalse(controlModule.authorizedFactories(factory));

        vm.expectEmit(true, false, false, true);
        emit FactoryAuthorized(factory, true);
        vm.prank(admin);
        controlModule.setFactoryAuthorization(factory, true);
    }

    function testFreezeAndUnfreezeAddress() public {
        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(ControlModule.ControlModule__AssetNotAuthorized.selector));
        controlModule.freezeAddressForAsset(address(0x12345), user);

        vm.prank(operator);
        controlModule.freezeAddressForAsset(address(asset), user);

        // Confirm frozen address triggered event
        vm.expectEmit(true, true, false, false);
        emit AssetFrozen(address(asset), user);
        vm.prank(operator);
        controlModule.freezeAddressForAsset(address(asset), user);

        // Asset contract should reflect frozen address
        bool frozen = AssetContract(address(asset)).frozenAddresses(user);
        assertTrue(frozen);

        vm.prank(operator);
        controlModule.unfreezeAddressForAsset(address(asset), user);

        frozen = AssetContract(address(asset)).frozenAddresses(user);
        assertFalse(frozen);
    }

    function testFreezeAndUnfreezeAsset() public {
        vm.prank(operator);
        // Freeze with unauthorized asset reverts
        vm.expectRevert(abi.encodeWithSelector(ControlModule.ControlModule__AssetNotAuthorized.selector));
        controlModule.freezeAsset(address(0x123456));

        vm.prank(operator);
        controlModule.freezeAsset(address(asset));
        bool frozen = AssetContract(address(asset)).assetFrozen();
        assertTrue(frozen);

        vm.expectEmit(true, false, false, false);
        emit AssetGloballyFrozen(address(asset));
        vm.prank(operator);
        controlModule.freezeAsset(address(asset));

        vm.prank(operator);
        controlModule.unfreezeAsset(address(asset));
        frozen = AssetContract(address(asset)).assetFrozen();
        assertFalse(frozen);

        vm.expectEmit(true, false, false, false);
        emit AssetGloballyUnfrozen(address(asset));
        vm.prank(operator);
        controlModule.unfreezeAsset(address(asset));
    }

    function testUpdateCollateralRatio() public {
        vm.prank(assetManager);
        vm.expectRevert(abi.encodeWithSelector(ControlModule.ControlModule__AssetNotAuthorized.selector));
        controlModule.updateAssetCollateralRatio(address(0x123), 5000);

        vm.prank(operator);
        vm.expectRevert(
            "AccessControl: account 0x000000000000000000000000000000000000beef is missing role 0xb1fadd3142ab2ad7f1337ea4d97112bcc8337fc11ce5b20cb04ad038adf99819"
        );
        controlModule.updateAssetCollateralRatio(address(asset), 5000);

        vm.prank(assetManager);
        vm.expectRevert(abi.encodeWithSelector(ControlModule.ControlModule__RatioTooHigh.selector));
        controlModule.updateAssetCollateralRatio(address(asset), 20_000);

        vm.prank(assetManager);
        controlModule.updateAssetCollateralRatio(address(asset), 7500);

        AssetContract.AssetInfo memory assetInfo = asset.getAssetInfo();
        assertEq(assetInfo.collateralRatio, 7500);
    }

    function testRegisterAsset() public {
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(ControlModule.ControlModule__UnauthorizedFactory.selector));
        controlModule.registerAsset(address(0xFFF));

        vm.prank(admin);
        controlModule.setFactoryAuthorization(user, true);

        vm.prank(user);
        controlModule.registerAsset(address(0xFFF));
        assertTrue(controlModule.authorizedAssets(address(0xFFF)));
    }

    function testMintAndBurn() public {
        vm.prank(user);
        vm.expectRevert(
            "AccessControl: account 0x000000000000000000000000000000000000aaaa is missing role 0x9f2df0fed2c77648de5860a4cc508cd0818c85b8b8a1ab4ceeef8d981c8956a6"
        );
        asset.mint(user, 100 ether, 50 ether, 10 ether);

        vm.startPrank(admin);
        underlying.transfer(admin, 200 ether);
        underlying.approve(address(asset), type(uint256).max);
        asset.mint(user, 100 ether, 50 ether, 10 ether);

        AssetContract.CollateralInfo memory collateralInfo = asset.getCollateralInfo();
        assertEq(collateralInfo.onChainAmount, 50 ether);
        assertEq(collateralInfo.offChainAmount, 10 ether);

        uint256 userBalance = asset.balanceOf(user);
        assertEq(userBalance, 100 ether);

        asset.burn(user, 50 ether);
        userBalance = asset.balanceOf(user);
        assertEq(userBalance, 50 ether);

        vm.stopPrank();
    }

    function testMintFailsWithFrozenAddress() public {
        vm.prank(operator);
        controlModule.freezeAddressForAsset(address(asset), user);

        vm.startPrank(admin);
        underlying.approve(address(asset), 100 ether);
        vm.expectRevert(abi.encodeWithSelector(AssetContract.AssetContract__AddressFrozen.selector));
        asset.mint(user, 100 ether, 0, 0);
        vm.stopPrank();
    }

    function testBurnFailsWithInsufficientBalance() public {
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(AssetContract.AssetContract__InsufficientBalance.selector));
        asset.burn(user, 1);
    }

    function testVaultAuthorizationAndDepositWithdraw() public {
        vm.prank(admin);
        asset.authorizeVault(address(vault));

        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(AssetContract.AssetContract__InvalidVault.selector));
        asset.authorizeVault(address(0));

        vm.prank(admin);
        asset.deauthorizeVault(address(vault));

        vm.prank(admin);
        // re-authorize for deposit/withdraw
        asset.authorizeVault(address(vault));

        vm.prank(admin);
        // Approve underlying token to asset contract for depositToVault
        underlying.approve(address(asset), 50 ether);

        vm.prank(admin);
        asset.depositToVault(address(vault), 50 ether);

        vm.prank(admin);
        asset.withdrawFromVault(address(vault), 25 ether);
    }

    function testVaultDepositWithdrawFailsWithoutAuthorization() public {
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(AssetContract.AssetContract__VaultNotAuthorized.selector));
        asset.depositToVault(address(0x123456), 10 ether);

        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(AssetContract.AssetContract__VaultNotAuthorized.selector));
        asset.withdrawFromVault(address(0x123456), 10 ether);
    }

    function testFreezeUnfreezeAddressOnlyControlModule() public {
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(AssetContract.AssetContract__OnlyControlModule.selector));
        asset.freezeAddress(user);

        vm.prank(address(controlModule));
        asset.freezeAddress(user);

        bool frozen = asset.frozenAddresses(user);
        assertTrue(frozen);

        vm.prank(address(controlModule));
        asset.unfreezeAddress(user);

        frozen = asset.frozenAddresses(user);
        assertFalse(frozen);
    }

    function testFreezeUnfreezeAssetOnlyControlModule() public {
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(AssetContract.AssetContract__OnlyControlModule.selector));
        asset.freezeAsset();

        vm.prank(address(controlModule));
        asset.freezeAsset();
        assertTrue(asset.assetFrozen());

        vm.prank(address(controlModule));
        asset.unfreezeAsset();
        assertFalse(asset.assetFrozen());
    }

    function testUpdateCollateralRatioOnlyControlModule() public {
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(AssetContract.AssetContract__OnlyControlModule.selector));
        asset.updateCollateralRatio(5000);

        vm.prank(address(controlModule));
        asset.updateCollateralRatio(5000);

        AssetContract.AssetInfo memory assetInfo = asset.getAssetInfo();
        assertEq(assetInfo.collateralRatio, 5000);

        vm.prank(address(controlModule));
        vm.expectRevert(abi.encodeWithSelector(AssetContract.AssetContract__InvalidRatio.selector));
        asset.updateCollateralRatio(20_000);
    }

    function testGetAssetAtOutOfBounds() public {
        vm.expectRevert(abi.encodeWithSelector(AssetFactory.AssetFactory__IndexOutOfBounds.selector));
        assetFactory.getAssetAt(100);
    }
}
