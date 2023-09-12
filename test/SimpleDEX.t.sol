// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import "src/SimpleDEX.sol";
import "./helper/MockERC20.sol";

contract TestSimpleDEX is Test {
    // Global variables
    SimpleDEX dex;
    MockERC20 baseToken;
    MockERC20 quoteToken;

    uint256 internal deployerPrivateKey;
    uint256 internal makerPrivateKey;
    uint256 internal takerPrivateKey;

    // Constants
    uint256 internal constant INIT_BALANCE = 100;

    function setUp() public {
        deployerPrivateKey = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
        makerPrivateKey = 0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d;
        takerPrivateKey = 0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a;

        // Deploy SimpleDEX contract
        vm.prank(vm.addr(deployerPrivateKey), vm.addr(deployerPrivateKey));
        dex = new SimpleDEX();

        // Create ERC20 tokens
        baseToken = new MockERC20("BaseToken", "BT");
        quoteToken = new MockERC20("QuoteToken", "QT");

        // Mint ERC20 tokens
        baseToken.mint(address(vm.addr(makerPrivateKey)), INIT_BALANCE);
        vm.deal(address(vm.addr(makerPrivateKey)), 10 ether);

        quoteToken.mint(address(vm.addr(takerPrivateKey)), INIT_BALANCE);
        vm.deal(address(vm.addr(takerPrivateKey)), 10 ether);
    }

    // Deposit and Withdrawal
    function testContractOwner() external {
        address deployerAddress = dex.owner();
        assertEq(
            deployerAddress,
            vm.addr(deployerPrivateKey),
            "deployerAddress != ownerAddress"
        );
    }

    function testAddSupportedToken() external {
        // Act
        vm.startPrank(vm.addr(deployerPrivateKey));
        dex.addSupportedToken(address(baseToken));
        dex.addSupportedToken(address(quoteToken));
        vm.stopPrank();

        bool isBaseTokenSupported = dex.supportedTokens(address(baseToken));
        bool isQuoteTokenSupported = dex.supportedTokens(address(quoteToken));

        // Assert
        assertTrue(isBaseTokenSupported, "baseToken is not supported");
        assertTrue(isQuoteTokenSupported, "quoteToken is not supported");
    }

    function testDepositUnSupportedToken() external {
        // Arrange
        uint256 amount = 10;

        // Act
        vm.prank(vm.addr(makerPrivateKey));
        vm.expectRevert(bytes("Token not supported"));
        dex.deposit(address(baseToken), amount);

        uint256 balance = dex.userBalances(
            address(vm.addr(makerPrivateKey)),
            address(baseToken)
        );

        // Assert
        assertEq(balance, 0, "balance should be 0");
        assertTrue(balance != amount, "balance should not be 10");
    }

    function testDepositSupportedToken() external {
        // Arrange
        uint256 amount = 10;

        // Act
        // Add supported tokens
        vm.startPrank(vm.addr(deployerPrivateKey));
        dex.addSupportedToken(address(baseToken));
        vm.stopPrank();

        uint256 makerBaseTokenBalance = baseToken.balanceOf(
            address(vm.addr(makerPrivateKey))
        );
        assertEq(makerBaseTokenBalance, INIT_BALANCE, "balance should be 100");

        // Deposit supported tokens
        vm.startPrank(vm.addr(makerPrivateKey));
        baseToken.approve(address(dex), amount);
        dex.deposit(address(baseToken), amount);
        vm.stopPrank();

        uint256 balance = dex.userBalances(
            address(vm.addr(makerPrivateKey)),
            address(baseToken)
        );

        uint256 makerBaseTokenBalanceAfter = baseToken.balanceOf(
            address(vm.addr(makerPrivateKey))
        );

        // Assert
        assertEq(balance, amount, "balance should be 10");
        assertEq(makerBaseTokenBalanceAfter, INIT_BALANCE - amount);
        assertLt(makerBaseTokenBalanceAfter, makerBaseTokenBalance);
    }

    function testWithdrawalUnSupportedToken() external {
        // Arrange
        uint256 amount = 10;

        // Act
        vm.prank(vm.addr(makerPrivateKey));
        vm.expectRevert(bytes("Token not supported"));
        dex.withdraw(address(baseToken), amount);

        uint256 balance = dex.userBalances(
            address(vm.addr(makerPrivateKey)),
            address(baseToken)
        );

        // Assert
        assertEq(balance, 0, "balance should be 0");
        assertTrue(balance != amount, "balance should not be 10");
    }

    function testWithdrawalSupportedToken() external {
        // Arrange
        uint256 amount = 10;

        // Act

        // Add supported tokens
        vm.startPrank(vm.addr(deployerPrivateKey));
        dex.addSupportedToken(address(baseToken));
        vm.stopPrank();

        uint256 makerBaseTokenBalance = baseToken.balanceOf(
            address(vm.addr(makerPrivateKey))
        );
        assertEq(makerBaseTokenBalance, INIT_BALANCE);

        // Deposit supported tokens
        vm.startPrank(vm.addr(makerPrivateKey));
        baseToken.approve(address(dex), amount);
        dex.deposit(address(baseToken), amount);
        vm.stopPrank();

        uint256 balance = dex.userBalances(
            address(vm.addr(makerPrivateKey)),
            address(baseToken)
        );

        uint256 makerBaseTokenBalanceAfter = baseToken.balanceOf(
            address(vm.addr(makerPrivateKey))
        );

        // Assert
        assertEq(balance, amount, "balance should be 10");
        assertEq(makerBaseTokenBalanceAfter, INIT_BALANCE - amount);
        assertLt(makerBaseTokenBalanceAfter, makerBaseTokenBalance);

        // Withdraw supported tokens
        vm.startPrank(vm.addr(makerPrivateKey));
        dex.withdraw(address(baseToken), amount);
        vm.stopPrank();

        uint256 balanceAfter = dex.userBalances(
            address(vm.addr(makerPrivateKey)),
            address(baseToken)
        );

        uint256 makerBaseTokenBalanceAfterWithdrawal = baseToken.balanceOf(
            address(vm.addr(makerPrivateKey))
        );

        // Assert
        assertEq(balanceAfter, 0, "balance should be 0");
        assertEq(makerBaseTokenBalanceAfterWithdrawal, INIT_BALANCE);
        assertEq(makerBaseTokenBalanceAfterWithdrawal, makerBaseTokenBalance);
    }

    function testWithdrawalInsufficientBalance() external {
        // Arrange
        uint256 amount = 10;
        uint256 amountToWithdraw = 20;

        // Act

        // Add supported tokens
        vm.startPrank(vm.addr(deployerPrivateKey));
        dex.addSupportedToken(address(baseToken));
        vm.stopPrank();

        uint256 makerBaseTokenBalance = baseToken.balanceOf(
            address(vm.addr(makerPrivateKey))
        );
        assertEq(makerBaseTokenBalance, INIT_BALANCE);

        // Deposit supported tokens
        vm.startPrank(vm.addr(makerPrivateKey));
        baseToken.approve(address(dex), amount);
        dex.deposit(address(baseToken), amount);
        vm.stopPrank();

        uint256 balance = dex.userBalances(
            address(vm.addr(makerPrivateKey)),
            address(baseToken)
        );

        uint256 makerBaseTokenBalanceAfter = baseToken.balanceOf(
            address(vm.addr(makerPrivateKey))
        );

        // Assert
        assertEq(balance, amount, "balance should be 10");
        assertEq(makerBaseTokenBalanceAfter, INIT_BALANCE - amount);
        assertLt(makerBaseTokenBalanceAfter, makerBaseTokenBalance);

        // Withdraw supported tokens
        vm.startPrank(vm.addr(makerPrivateKey));
        vm.expectRevert(bytes("Insufficient balance"));
        dex.withdraw(address(baseToken), amountToWithdraw);
        vm.stopPrank();

        uint256 balanceAfter = dex.userBalances(
            address(vm.addr(makerPrivateKey)),
            address(baseToken)
        );

        uint256 makerBaseTokenBalanceAfterWithdrawal = baseToken.balanceOf(
            address(vm.addr(makerPrivateKey))
        );

        // Assert
        assertEq(balanceAfter, balance, "balance should not change");
        assertEq(
            makerBaseTokenBalanceAfterWithdrawal + amount,
            makerBaseTokenBalance
        );
    }
}
