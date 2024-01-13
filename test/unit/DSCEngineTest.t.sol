// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
// my imports
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";

contract DSCEngineTest is Test {
    DeployDSC deployer;
    DecentralizedStableCoin dsc;
    DSCEngine dsce;
    HelperConfig config;
    address ethUsdPriceFeed;
    address btcUsdPriceFeed;
    address weth;

    address public USER = makeAddr("user");
    // my users
    address public USER_2 = makeAddr("user_2");
    // end my users
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant STARTING_ERC20_BALANCE = 10 ether;
    // my constants
    uint256 public constant AMOUNT_DSC_TO_MINT = 100 ether;
    uint256 public constant AMOUNT_DSC_TO_MINT_REVERT = 100000 ether;
    uint256 public constant ZERO = 0;
    // end my constants

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, dsce, config) = deployer.run();
        (ethUsdPriceFeed, btcUsdPriceFeed, weth,,) = config.activeNetworkConfig();
        ERC20Mock(weth).mint(USER, STARTING_ERC20_BALANCE);
    }

    //////////////////////////
    // Constructor Tests /////
    //////////////////////////
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function testRevertsIfTokenLengthDoesntMatchPriceFeeds() public {
        tokenAddresses.push(weth);
        priceFeedAddresses.push(ethUsdPriceFeed);
        priceFeedAddresses.push(btcUsdPriceFeed);

        vm.expectRevert(DSCEngine.DSCEngine__TokenAddressesAndPriceFeedsMustBeSameLength.selector);
        new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
    }

    ////////////////////
    // Price Tests /////
    ////////////////////

    function testGetUsdValue() public {
        uint256 ethAmount = 15e18;
        uint256 expectedUsd = 30000e18;
        uint256 actualUsd = dsce.getUsdValue(weth, ethAmount);
        assertEq(expectedUsd, actualUsd);
    }

    function testGetTokenAmountFromUsd() public {
        uint256 usdAmount = 100 ether;
        uint256 expectedWeth = 0.05 ether;
        uint256 actualWeth = dsce.getTokenAmountFromUsd(weth, usdAmount);
        assertEq(expectedWeth, actualWeth);
    }

    ////////////////////////////////
    // depositCollateral Tests /////
    ////////////////////////////////

    function testRevertsIfCollateralZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dsce.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    function testRevertsWithUnapprovedCollateral() public {
        ERC20Mock ranToken = new ERC20Mock();
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NotAllowedToken.selector);
        dsce.depositCollateral(address(ranToken), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    modifier depositedCollateral() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    function testCanDepositCollateralAndGetAccountInfo() public depositedCollateral {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dsce.getAccountInformation(USER);
        uint256 expectedTotalDscMinted = 0;
        uint256 expectedDepositAmount = dsce.getTokenAmountFromUsd(weth, collateralValueInUsd);
        assertEq(totalDscMinted, expectedTotalDscMinted);
        assertEq(AMOUNT_COLLATERAL, expectedDepositAmount);
    }

    // MY TEST //
    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);

    function testDepositCollateralEmitsEvent() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        vm.expectEmit(address(dsce));
        emit CollateralDeposited(USER, weth, AMOUNT_COLLATERAL);
        dsce.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    //////////////////////
    // mintDsc Tests /////
    /////////////////////

    modifier dscMinted() {
        vm.prank(USER);
        dsce.mintDsc(AMOUNT_DSC_TO_MINT);
        _;
    }

    function testMintDscRevertsWhenAmountDscToMintIsZero() public depositedCollateral {
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dsce.mintDsc(0);
        vm.stopPrank();
    }

    function testMintDscAndGetAmountMinted() public depositedCollateral dscMinted {
        uint256 expectedAmountToMint = dsce.getDscMinted(USER);
        assertEq(expectedAmountToMint, AMOUNT_DSC_TO_MINT);
    }

    function testRevertIfExpectHealthFactorIsBroken() public depositedCollateral {
        vm.prank(USER);
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__BreaksHealthFactor.selector, 100000000000000000));
        dsce.mintDsc(AMOUNT_DSC_TO_MINT_REVERT);
    }

    ////////////////////////
    // liquidate Tests /////
    ////////////////////////

    function testRevertIfLiquidateIsCalledWithZeroDebtToCover() public {
        vm.prank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dsce.liquidate(weth, USER_2, ZERO);
    }

    function testShouldRevertIfHealthFactorIsOk() public depositedCollateral dscMinted {
        vm.prank(USER_2);
        vm.expectRevert(DSCEngine.DSCEngine__HealthFactorOk.selector);
        dsce.liquidate(weth, USER, AMOUNT_COLLATERAL);
    }

    // THIS FUNCTION NEEDS FIXING
    // function testIfItIsGoingToRevert() public {
    //     vm.startPrank(USER);
    //     ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
    //     dsce.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, AMOUNT_DSC_TO_MINT);
    //     vm.stopPrank();

    //     MockV3Aggregator(ethUsdPriceFeed).updateAnswer(1000);

    //     vm.startPrank(USER_2);
    //     console.log(address(dsce));
    //     ERC20Mock(weth).approve(address(dsce), 1000000 ether);
    //     dsce.liquidate(weth, USER, 1 ether);
    //     vm.stopPrank();
    // }

    //////////////////////////////////////////
    // depositCollateralAndMintDsc Tests /////
    //////////////////////////////////////////

    function testDepositCollateralAndMintDscDepositsCollateralAndMintsDsc() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, AMOUNT_DSC_TO_MINT);
        vm.stopPrank();
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dsce.getAccountInformation(USER);
        uint256 expectedCollateralValueInUsd = dsce.getUsdValue(weth, AMOUNT_COLLATERAL);
        assertEq(totalDscMinted, AMOUNT_DSC_TO_MINT);
        assertEq(expectedCollateralValueInUsd, collateralValueInUsd);
    }

    /////////////////////////////////////
    // redeemCollateralForDsc Tests /////
    /////////////////////////////////////

    function testCanRedeemDepositedCollateral() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, AMOUNT_DSC_TO_MINT);
        dsc.approve(address(dsce), AMOUNT_DSC_TO_MINT);
        dsce.redeemCollateralForDsc(weth, AMOUNT_COLLATERAL, AMOUNT_DSC_TO_MINT);
        vm.stopPrank();

        uint256 userBalance = dsc.balanceOf(USER);
        assertEq(userBalance, 0);
    }

    ///////////////////////////////
    // redeemCollateral Tests /////
    ///////////////////////////////

    function testRedeemCollateralReverts() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, AMOUNT_DSC_TO_MINT);
        dsc.approve(address(dsce), AMOUNT_DSC_TO_MINT);
        dsce.burnDsc(AMOUNT_DSC_TO_MINT);
        dsc.approve(address(dsce), AMOUNT_DSC_TO_MINT);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dsce.redeemCollateral(weth, ZERO);
        vm.stopPrank();

        uint256 userBalance = dsc.balanceOf(USER);
        assertEq(userBalance, 0);
    }

    //////////////////////////////
    // getHealthFactor Tests /////
    //////////////////////////////

    function testgetHealthFactor() public depositedCollateral dscMinted {
        vm.prank(USER);
        uint256 healthFactor = dsce.getHealthFactor();
        uint256 expectedHealthFactor = 100000000000000000000;
        console.log(healthFactor);
        assertEq(expectedHealthFactor, healthFactor);
    }

    ////////////////////////////////////////
    // getAccountCollateralValue Tests /////
    ////////////////////////////////////////

    function testGetAccountCollateralValue() public depositedCollateral {
        uint256 collataralValue = dsce.getAccountCollateralValue(USER);
        uint256 expectedCollateralValue = 20000000000000000000000;
        assertEq(collataralValue, expectedCollateralValue);
    }

    ////////////////////////////////////
    // calculateHealthFactor Tests /////
    ////////////////////////////////////

    function testCalculateHealthFactor() public depositedCollateral dscMinted {
        uint256 healthFactor = dsce.calculateHealthFactor(AMOUNT_DSC_TO_MINT, 20000000000000000000000);
        uint256 expectedHeathFactor = 100000000000000000000;
        assertEq(healthFactor, expectedHeathFactor);
    }

    // 85% - 90%
}
