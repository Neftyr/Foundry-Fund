// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {FundMe} from "../../src/FundMe.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {DeployFundMe} from "../../script/DeployFundMe.s.sol";

contract FundMeTest is Test {
    /** Tests
     1. Unit
        - Testing a specific part of our code
     2. Integration 
        - Testing how our code works with other parts of our code
     3. Forked
        - Testing our code on simulated real environment
     4. Staging
        - Testing our code in a real environment that is not production
    */

    FundMe public fundMe;
    HelperConfig public helperConfig;
    address public priceFeed;

    address deploy;
    /// @dev `makeAddr()` this function allows us to create new address based on given name (this address will have 0 balance)
    address public immutable i_user = makeAddr("Niferu");
    /// @dev we can also make i_user like below
    address public constant ANOTHER_USER = address(1);

    uint256 public constant SEND_VALUE = 0.1 ether;
    uint256 public constant STARTING_USER_BALANCE = 10 ether;
    uint256 public constant GAS_PRICE = 1;

    /// @dev Another ways to write eth
    // uint256 public constant SEND_VALUE = 1e18;
    // uint256 public constant SEND_VALUE = 1000000000000000000;
    // uint256 public constant SEND_VALUE = 1_000_000_000_000_000_000;

    function setUp() external {
        DeployFundMe deployer = new DeployFundMe();
        deploy = address(deployer);
        console.log("Deploy Contract Address: ", deploy);
        (fundMe, helperConfig) = deployer.run();
        priceFeed = helperConfig.activeNetworkConfig();

        /// @dev adding funds to our i_user by using foundry function `deal()`
        // vm.deal(i_user, 10 ether) will work also
        deal(i_user, 10 ether);
    }

    function testMinimumDollarIsFive() public {
        assertEq(fundMe.MINIMUM_USD(), 5e18);
    }

    function testOwnerIsMsgSender() public {
        assertEq(fundMe.getOwner(), msg.sender);
    }

    function testPriceFeed() public {
        uint256 version = fundMe.getVersion();
        address feed = address(fundMe.getPriceFeed());

        assertEq(version, 4);
        assertEq(feed, priceFeed);
    }

    function testFundFailsWithoutEnoughETH() public {
        /// @dev Next line should revert
        vm.expectRevert();
        fundMe.fund{value: 1 wei}();
    }

    function testFundUpdatesData() public {
        /// @dev `prank` keyword sets msg.sender to the specific address for the next call
        vm.prank(i_user);
        console.log(i_user);

        fundMe.fund{value: 1 ether}();

        uint256 amountFunded = fundMe.getAddressToAmountFunded(i_user);
        address funder = fundMe.getFunder(0);

        /// @dev We can use both assertions
        assertEq(amountFunded, 1 ether);
        assert(funder == i_user);
    }

    function testOnlyOwnerCanWithdraw() public funded {
        // Calling withdraw as not owner
        vm.prank(i_user);
        vm.expectRevert();
        fundMe.withdraw();

        // Checking owner
        assert(fundMe.getOwner() == msg.sender);

        // Calling withdraw as owner
        vm.startPrank(msg.sender);
        fundMe.withdraw();
        vm.stopPrank();
    }

    function testWithdrawFromASingleFunder() public funded {
        // Arrange
        uint256 startingFundMeBalance = address(fundMe).balance;
        uint256 startingOwnerBalance = fundMe.getOwner().balance;
        console.log("FundMe: ", startingFundMeBalance, "Owner: ", startingOwnerBalance);

        assertEq(startingFundMeBalance, SEND_VALUE);

        /// @dev Adding transaction gas cost for next tx (our foundry is setting gasCost to 0 as default)
        vm.txGasPrice(GAS_PRICE);
        uint256 gasStart = gasleft();

        // Act
        vm.startPrank(fundMe.getOwner());
        fundMe.withdraw();
        vm.stopPrank();

        uint256 gasEnd = gasleft();
        uint256 gasUsed = (gasStart - gasEnd) * tx.gasprice;
        console.log("Gas: ", gasUsed);
        /// @dev This above gas thing has no effect on our balances

        // Assert
        uint256 endingFundMeBalance = address(fundMe).balance;
        uint256 endingOwnerBalance = fundMe.getOwner().balance;
        assertEq(endingFundMeBalance, 0);
        assertEq(startingFundMeBalance + startingOwnerBalance, endingOwnerBalance);
    }

    // Can we do our withdraw function a cheaper way?
    function testWithDrawFromMultipleFunders() public funded {
        /// @dev We are using uint160 here as it is having same amount of bytes as address, so we can cast uint160(address)
        uint160 numberOfFunders = 10;
        uint160 startingFunderIndex = 2;

        for (uint160 i = startingFunderIndex; i < numberOfFunders + startingFunderIndex; i++) {
            /// @dev `hoax()` function is prank() + deal()
            hoax(address(i), STARTING_USER_BALANCE);
            fundMe.fund{value: SEND_VALUE}();
        }

        uint256 startingFundMeBalance = address(fundMe).balance;
        uint256 startingOwnerBalance = fundMe.getOwner().balance;

        vm.startPrank(fundMe.getOwner());
        fundMe.withdraw();
        vm.stopPrank();

        assert(address(fundMe).balance == 0);
        assert(startingFundMeBalance + startingOwnerBalance == fundMe.getOwner().balance);
        assert((numberOfFunders + 1) * SEND_VALUE == fundMe.getOwner().balance - startingOwnerBalance);
    }

    function testWithDrawFromMultipleFundersCheaper() public funded {
        /// @dev We are using uint160 here as it is having same amount of bytes as address, so we can cast uint160(address)
        uint160 numberOfFunders = 10;
        uint160 startingFunderIndex = 2;

        for (uint160 i = startingFunderIndex; i < numberOfFunders + startingFunderIndex; i++) {
            /// @dev `hoax()` function is prank() + deal()
            hoax(address(i), STARTING_USER_BALANCE);
            fundMe.fund{value: SEND_VALUE}();
        }

        uint256 startingFundMeBalance = address(fundMe).balance;
        uint256 startingOwnerBalance = fundMe.getOwner().balance;

        vm.startPrank(fundMe.getOwner());
        fundMe.cheaperWithdraw();
        vm.stopPrank();

        assert(address(fundMe).balance == 0);
        assert(startingFundMeBalance + startingOwnerBalance == fundMe.getOwner().balance);
        assert((numberOfFunders + 1) * SEND_VALUE == fundMe.getOwner().balance - startingOwnerBalance);
    }

    modifier funded() {
        vm.prank(i_user);
        fundMe.fund{value: SEND_VALUE}();
        assert(address(fundMe).balance > 0);
        _;
    }
}
