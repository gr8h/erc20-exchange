// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import "src/SimpleDEX.sol";
import "./helper/MockERC20.sol";

contract TestSimpleDEX is Test {
    // Global variables
    SimpleDEX public dex;
    MockERC20 public baseToken;
    MockERC20 public quoteToken;

    uint256 public deployerPrivateKey;
    uint256 public makerPrivateKey;
    uint256 public takerPrivateKey;

    // Constants
    uint256 internal constant _INIT_BALANCE = 100;

    // Events
    event TokenAdded(address indexed token);
    event Deposited(
        address indexed user,
        address indexed token,
        uint256 amount
    );
    event Withdrawn(
        address indexed user,
        address indexed token,
        uint256 amount
    );

    // Errors
    bytes4 public tokenNotSupportedSelector =
        bytes4(keccak256("TokenNotSupported(address)"));

    bytes4 public insufficientBalanceSelector =
        bytes4(keccak256("InsufficientBalance()"));

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
        baseToken.mint(address(vm.addr(makerPrivateKey)), _INIT_BALANCE);
        vm.deal(address(vm.addr(makerPrivateKey)), 10 ether);

        quoteToken.mint(address(vm.addr(takerPrivateKey)), _INIT_BALANCE);
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

        vm.expectEmit(true, false, false, true);
        emit TokenAdded(address(baseToken));
        dex.addSupportedToken(address(baseToken));

        vm.expectEmit(true, false, false, true);
        emit TokenAdded(address(quoteToken));
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
        vm.expectRevert(
            abi.encodeWithSelector(
                tokenNotSupportedSelector,
                address(baseToken)
            )
        );
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
        assertEq(makerBaseTokenBalance, _INIT_BALANCE, "balance should be 100");

        // Deposit supported tokens
        vm.startPrank(vm.addr(makerPrivateKey));
        baseToken.approve(address(dex), amount);

        vm.expectEmit(true, true, true, true);
        emit Deposited(
            address(vm.addr(makerPrivateKey)),
            address(baseToken),
            amount
        );

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
        assertEq(makerBaseTokenBalanceAfter, _INIT_BALANCE - amount);
        assertLt(makerBaseTokenBalanceAfter, makerBaseTokenBalance);
    }

    function testWithdrawalUnSupportedToken() external {
        // Arrange
        uint256 amount = 10;

        // Act
        vm.prank(vm.addr(makerPrivateKey));
        vm.expectRevert(
            abi.encodeWithSelector(
                tokenNotSupportedSelector,
                address(baseToken)
            )
        );
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
        assertEq(makerBaseTokenBalance, _INIT_BALANCE);

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
        assertEq(makerBaseTokenBalanceAfter, _INIT_BALANCE - amount);
        assertLt(makerBaseTokenBalanceAfter, makerBaseTokenBalance);

        // Withdraw supported tokens
        vm.startPrank(vm.addr(makerPrivateKey));
        vm.expectEmit(true, true, true, true);
        emit Withdrawn(
            address(vm.addr(makerPrivateKey)),
            address(baseToken),
            amount
        );
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
        assertEq(makerBaseTokenBalanceAfterWithdrawal, _INIT_BALANCE);
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
        assertEq(makerBaseTokenBalance, _INIT_BALANCE);

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
        assertEq(makerBaseTokenBalanceAfter, _INIT_BALANCE - amount);
        assertLt(makerBaseTokenBalanceAfter, makerBaseTokenBalance);

        // Withdraw supported tokens
        vm.startPrank(vm.addr(makerPrivateKey));
        vm.expectRevert(abi.encodeWithSelector(insufficientBalanceSelector));
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
