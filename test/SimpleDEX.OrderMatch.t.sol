// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import "src/SimpleDEX.sol";
import "./helper/MockERC20.sol";
import "./helper/MockERC20Decimal6.sol";
import "openzeppelin-contracts/utils/cryptography/ECDSA.sol";

contract TestSimpleDEX is Test {
    using ECDSA for bytes32;
    // Global variables
    SimpleDEX public dex;
    MockERC20 public mockWETH;
    MockERC20Decimal6 public mockUSDC;

    uint256 public deployerPrivateKey;
    uint256 public makerPrivateKey;
    uint256 public takerPrivateKey;

    // Constants
    uint256 internal constant _PRESENT_DAY = 1680616584;

    // Events
    event OrderMatched(
        address indexed baseToken,
        address indexed quoteToken,
        address maker,
        address taker,
        uint256 indexed price,
        uint256 amount
    );

    // Modifier
    modifier startAtPresentDay() {
        vm.warp(_PRESENT_DAY);
        _;
    }

    // Helpers
    function _generateSignature(
        uint256 privateKey,
        SimpleDEX.Order memory order
    ) internal returns (bytes memory) {
        uint8 v;
        bytes32 r;
        bytes32 s;

        bytes32 orderHash = dex.getOrderHash(order).toEthSignedMessageHash();

        (v, r, s) = vm.sign(privateKey, orderHash);

        return abi.encodePacked(r, s, v);
    }

    function setUp() public {
        deployerPrivateKey = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
        makerPrivateKey = 0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d;
        takerPrivateKey = 0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a;

        // Deploy SimpleDEX contract
        vm.prank(vm.addr(deployerPrivateKey), vm.addr(deployerPrivateKey));
        dex = new SimpleDEX();

        // Create ERC20 tokens
        mockWETH = new MockERC20("Wrapped ETH", "WETH");
        mockUSDC = new MockERC20Decimal6("USDCoin", "USDC");

        vm.deal(address(vm.addr(makerPrivateKey)), 10 ether);
        vm.deal(address(vm.addr(takerPrivateKey)), 10 ether);

        // Add supported tokens
        vm.startPrank(vm.addr(deployerPrivateKey));
        dex.addSupportedToken(address(mockWETH));
        dex.addSupportedToken(address(mockUSDC));
        vm.stopPrank();

        // Mint
        mockUSDC.mint(address(vm.addr(makerPrivateKey)), 100 * 10 ** 6);
        mockWETH.mint(address(vm.addr(takerPrivateKey)), 1 ether);

        // Deposit
        vm.startPrank(vm.addr(makerPrivateKey));
        mockUSDC.approve(address(dex), 100 * 10 ** 6);
        dex.deposit(address(mockUSDC), 100 * 10 ** 6);
        vm.stopPrank();
        assertEq(
            dex.userBalances(
                address(vm.addr(makerPrivateKey)),
                address(mockUSDC)
            ),
            100 * 10 ** 6
        );

        vm.startPrank(vm.addr(takerPrivateKey));
        mockWETH.approve(address(dex), 1 ether);
        dex.deposit(address(mockWETH), 1 ether);
        vm.stopPrank();
        assertEq(
            dex.userBalances(
                address(vm.addr(takerPrivateKey)),
                address(mockWETH)
            ),
            1 ether
        );
    }

    // Order Matching
    function testContractOwner() external {
        address deployerAddress = dex.owner();
        assertEq(
            deployerAddress,
            vm.addr(deployerPrivateKey),
            "deployerAddress != ownerAddress"
        );
    }

    // User A is the maker and willing to buy 1 WETH with 100 USDC, and User B is the taker wants to sell 1 WETH for 80 USDC.
    // Because A is the maker, the trade should happen at 80 USDC since it gives A the best price.
    // baseToken: ERC20 token address for the base asset (It is WETH in the WETH-USDC pair)
    // quoteToken: ERC20 token address for the quote asset (e.g., stablecoin, It is USDC in the WETH-USDC pair)
    function testMatchOrder() external startAtPresentDay {
        // Arrange
        uint8 v;
        bytes32 r;
        bytes32 s;

        // Ac

        // Maker: BUY 1 WETH for 100 USDC
        SimpleDEX.Order memory makerOrder = SimpleDEX.Order(
            1,
            address(vm.addr(makerPrivateKey)),
            SimpleDEX.TradeDirection.BUY,
            100,
            1 ether,
            _PRESENT_DAY + 1 days,
            address(mockWETH),
            address(mockUSDC)
        );

        bytes memory makerOrderSignature = _generateSignature(
            makerPrivateKey,
            makerOrder
        );

        assertEq(makerOrderSignature.length, 65);

        // Taker: SELL 1 WETH for 80 USDC
        SimpleDEX.Order memory takerOrder = SimpleDEX.Order(
            1,
            address(vm.addr(takerPrivateKey)),
            SimpleDEX.TradeDirection.SELL,
            80,
            1 ether,
            _PRESENT_DAY + 1 days,
            address(mockWETH),
            address(mockUSDC)
        );
        bytes32 takerOrderHash = dex
            .getOrderHash(takerOrder)
            .toEthSignedMessageHash();
        (v, r, s) = vm.sign(takerPrivateKey, takerOrderHash);
        bytes memory takerOrderSignature = _generateSignature(
            takerPrivateKey,
            takerOrder
        );

        // Assert
        vm.expectEmit(true, true, true, true);
        emit OrderMatched(
            makerOrder.baseToken,
            takerOrder.quoteToken,
            makerOrder.sender,
            takerOrder.sender,
            80 * 10 ** 6,
            1 ether
        );

        // Match orders
        vm.startPrank(vm.addr(deployerPrivateKey));
        dex.matchOrders(
            makerOrder,
            makerOrderSignature,
            takerOrder,
            takerOrderSignature
        );
        vm.stopPrank();
    }

    // should fail to match orders with expired maker order
    function testMatchExpiredOrder() external startAtPresentDay {
        // Ac

        // Maker: BUY 1 WETH for 100 USDC
        SimpleDEX.Order memory makerOrder = SimpleDEX.Order(
            1,
            address(vm.addr(makerPrivateKey)),
            SimpleDEX.TradeDirection.BUY,
            100,
            1 ether,
            _PRESENT_DAY + 1 days,
            address(mockWETH),
            address(mockUSDC)
        );

        bytes memory makerOrderSignature = _generateSignature(
            makerPrivateKey,
            makerOrder
        );

        // Taker: SELL 1 WETH for 80 USDC
        SimpleDEX.Order memory takerOrder = SimpleDEX.Order(
            1,
            address(vm.addr(takerPrivateKey)),
            SimpleDEX.TradeDirection.SELL,
            80,
            1 ether,
            _PRESENT_DAY - 2 days,
            address(mockWETH),
            address(mockUSDC)
        );

        bytes memory takerOrderSignature = _generateSignature(
            takerPrivateKey,
            takerOrder
        );

        // Assert

        // Match orders
        vm.startPrank(vm.addr(deployerPrivateKey));
        vm.expectRevert(bytes("Order has expired"));
        dex.matchOrders(
            makerOrder,
            makerOrderSignature,
            takerOrder,
            takerOrderSignature
        );
        vm.stopPrank();
    }

    // should fail to match orders with different token pairs
    function testMatchWrongPairOrder() external startAtPresentDay {
        // Ac

        // Maker: BUY 1 WETH for 100 USDC
        SimpleDEX.Order memory makerOrder = SimpleDEX.Order(
            1,
            address(vm.addr(makerPrivateKey)),
            SimpleDEX.TradeDirection.BUY,
            100,
            1 ether,
            _PRESENT_DAY + 1 days,
            address(mockWETH),
            address(mockUSDC)
        );

        bytes memory makerOrderSignature = _generateSignature(
            makerPrivateKey,
            makerOrder
        );

        // Taker: SELL 1 WETH for 80 USDC
        SimpleDEX.Order memory takerOrder = SimpleDEX.Order(
            1,
            address(vm.addr(takerPrivateKey)),
            SimpleDEX.TradeDirection.SELL,
            80,
            1 ether,
            _PRESENT_DAY + 1 days,
            address(mockUSDC),
            address(mockWETH)
        );

        bytes memory takerOrderSignature = _generateSignature(
            takerPrivateKey,
            takerOrder
        );

        // Assert

        // Match orders
        vm.startPrank(vm.addr(deployerPrivateKey));
        vm.expectRevert(bytes("Token pair mismatch"));
        dex.matchOrders(
            makerOrder,
            makerOrderSignature,
            takerOrder,
            takerOrderSignature
        );
        vm.stopPrank();
    }

    // should fail to match orders with same trade direction
    function testMatchSameDirectionOrder() external startAtPresentDay {
        // Ac

        // Maker: BUY 1 WETH for 100 USDC
        SimpleDEX.Order memory makerOrder = SimpleDEX.Order(
            1,
            address(vm.addr(makerPrivateKey)),
            SimpleDEX.TradeDirection.BUY,
            100,
            1 ether,
            _PRESENT_DAY + 1 days,
            address(mockWETH),
            address(mockUSDC)
        );

        bytes memory makerOrderSignature = _generateSignature(
            makerPrivateKey,
            makerOrder
        );

        // Taker: SELL 1 WETH for 80 USDC
        SimpleDEX.Order memory takerOrder = SimpleDEX.Order(
            1,
            address(vm.addr(takerPrivateKey)),
            SimpleDEX.TradeDirection.BUY,
            80,
            1 ether,
            _PRESENT_DAY + 1 days,
            address(mockWETH),
            address(mockUSDC)
        );

        bytes memory takerOrderSignature = _generateSignature(
            takerPrivateKey,
            takerOrder
        );

        // Assert

        // Match orders
        vm.startPrank(vm.addr(deployerPrivateKey));
        vm.expectRevert(bytes("Trade directions should be opposite"));
        dex.matchOrders(
            makerOrder,
            makerOrderSignature,
            takerOrder,
            takerOrderSignature
        );
        vm.stopPrank();
    }

    function testNounce() external startAtPresentDay {
        // Ac

        // Maker: BUY 1 WETH for 100 USDC
        SimpleDEX.Order memory makerOrder = SimpleDEX.Order(
            1,
            address(vm.addr(makerPrivateKey)),
            SimpleDEX.TradeDirection.BUY,
            100,
            1 ether,
            _PRESENT_DAY + 1 days,
            address(mockWETH),
            address(mockUSDC)
        );

        bytes memory makerOrderSignature = _generateSignature(
            makerPrivateKey,
            makerOrder
        );

        assertEq(makerOrderSignature.length, 65);

        // Taker: SELL 1 WETH for 80 USDC
        SimpleDEX.Order memory takerOrder = SimpleDEX.Order(
            1,
            address(vm.addr(takerPrivateKey)),
            SimpleDEX.TradeDirection.SELL,
            80,
            1 ether,
            _PRESENT_DAY + 1 days,
            address(mockWETH),
            address(mockUSDC)
        );

        bytes memory takerOrderSignature = _generateSignature(
            takerPrivateKey,
            takerOrder
        );

        // Assert
        vm.expectEmit(true, true, true, true);
        emit OrderMatched(
            makerOrder.baseToken,
            takerOrder.quoteToken,
            makerOrder.sender,
            takerOrder.sender,
            80 * 10 ** 6,
            1 ether
        );

        // Match orders
        vm.startPrank(vm.addr(deployerPrivateKey));
        dex.matchOrders(
            makerOrder,
            makerOrderSignature,
            takerOrder,
            takerOrderSignature
        );
        vm.stopPrank();

        vm.startPrank(vm.addr(deployerPrivateKey));
        vm.expectRevert(bytes("Maker nonce already used"));
        dex.matchOrders(
            makerOrder,
            makerOrderSignature,
            takerOrder,
            takerOrderSignature
        );
        vm.stopPrank();
    }
}
