// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import {IHelios, ERC1155TokenReceiver, HeliosReference} from "../HeliosReference.sol";
import {XYKswapper} from "../swappers/XYKswapper.sol";
import {MockERC20} from "@solbase/test/utils/mocks/MockERC20.sol";

import "forge-std/Test.sol";

contract HeliosReferenceTest is ERC1155TokenReceiver, Test {
    HeliosReference helios;
    XYKswapper xykSwapperContract;
    IHelios xykSwapper;
    address token0;
    address token1;
    address token2;

    /// @dev Pool ids.
    uint256 id01;
    uint256 id12;
    uint256 id02;
    uint256 id010;
    uint256 id120;
    uint256 id020;

    address deployer;

    function setUp() public {
        deployer = tx.origin;
        helios = new HeliosReference();
        xykSwapperContract = new XYKswapper();
        xykSwapper = IHelios(address(xykSwapperContract));

        token0 = address(new MockERC20("Token0", "TKN0", 18));
        token1 = address(new MockERC20("Token1", "TKN1", 18));
        token2 = address(new MockERC20("Token2", "TKN2", 18));
        require(token1 > token0 && token0 > token2, "tests assume addr(token1)>addr(token0)>addr(token2)");

        MockERC20(token0).mint(address(this), 1_000_000 ether);
        MockERC20(token1).mint(address(this), 1_000_000 ether);
        MockERC20(token2).mint(address(this), 1_000_000 ether);

        MockERC20(token0).approve(address(helios), 1_000_000_0 ether);
        MockERC20(token1).approve(address(helios), 1_000_000_0 ether);
        MockERC20(token2).approve(address(helios), 1_000_000_0 ether);

        (id01, ) = helios.createPair(address(this), token0, token1, 1_000 ether, 1_000 ether, xykSwapper, 30, "");
        (id12, ) = helios.createPair(address(this), token1, token2, 1_000 ether, 1_000 ether, xykSwapper, 30, "");
        (id02, ) = helios.createPair(address(this), token0, token2, 1_000 ether, 1_000 ether, xykSwapper, 30, "");

        (id010, ) = helios.createPair(address(this), token0, token1, 1_000 ether, 1_000 ether, xykSwapper, 0, "");
        (id120, ) = helios.createPair(address(this), token1, token2, 1_000 ether, 1_000 ether, xykSwapper, 0, "");
        (id020, ) = helios.createPair(address(this), token0, token2, 1_000 ether, 1_000 ether, xykSwapper, 0, "");
    }

    function testHeliosCreation() public payable {
        helios = new HeliosReference();
    }

    function testXYKpairCreation() public payable {
        helios.createPair(address(this), token0, token1, 1_000 ether, 1_000 ether, xykSwapper, 1, "");
    }

    function testAddLiquidity() public payable {
        (uint256 id, uint256 c) = helios.createPair(
            address(this),
            token0,
            token1,
            1_000 ether,
            1_000 ether,
            xykSwapper,
            1,
            ""
        );
        uint256 b = helios.addLiquidity(address(this), id, 1_000 ether, 1_000 ether, "");
        uint256 a = helios.addLiquidity(address(this), id, 1_000 ether, 1_000 ether, "");
        require(a == b, "a!=b");
        require(b == c, "b!=c");
    }

    function testXYKpairSwap(uint256 amountIn) public payable {
        uint256 b0 = MockERC20(token0).balanceOf(address(this));
        vm.assume(amountIn > 100000 && amountIn < b0);
        uint256 b1 = MockERC20(token1).balanceOf(address(this));

        (, , , uint112 q0, uint112 q1, ) = helios.pairs(id01);

        uint256 amountOut = helios.swap(address(this), id01, token0, amountIn);
        uint256 a0 = MockERC20(token0).balanceOf(address(this));
        uint256 a1 = MockERC20(token1).balanceOf(address(this));

        (, , , uint112 r0, uint112 r1, ) = helios.pairs(id01);

        if (q0 + amountIn != r0) {
            revert("reserve0 is wrong");
        }
        if (q1 - amountOut != r1) {
            revert("reserve0 is wrong");
        }
        if (b0 - amountIn != a0) {
            revert("Did not consume the right amount of token0");
        }
        if (b1 + amountOut != a1) {
            revert("Did not produce the right amount of token1");
        }
    }

    function testXYKpairMultiHop(uint256 amountIn) public payable {
        uint256 b0 = MockERC20(token0).balanceOf(address(this));
        vm.assume(amountIn > 100000 && amountIn < b0);
        uint256 b1 = MockERC20(token1).balanceOf(address(this));
        uint256 b2 = MockERC20(token2).balanceOf(address(this));

        (, , , uint112 p0, uint112 p1, ) = helios.pairs(id01);
        (, , , uint112 q2, uint112 q1, ) = helios.pairs(id12);

        uint256[] memory path = new uint256[](2);
        path[0] = id01;
        path[1] = id12;

        uint256 amountOut = helios.swap(address(this), path, token0, amountIn);

        (, , , uint112 r0, uint112 r1, ) = helios.pairs(id01);
        (, , , uint112 s2, uint112 s1, ) = helios.pairs(id12);

        if (p0 + amountIn != r0) {
            revert("reserve0 is wrong");
        }
        if (p1 + q1 != r1 + s1) {
            revert("hop token reserves are wrong");
        }
        if (q2 - amountOut != s2) {
            revert("reserve1 is wrong");
        }
        if (b0 - amountIn != MockERC20(token0).balanceOf(address(this))) {
            revert("Did not consume the right amount of token0");
        }
        if (b1 != MockERC20(token1).balanceOf(address(this))) {
            revert("Balance on hop token1 should not change");
        }
        if (b2 + amountOut != MockERC20(token2).balanceOf(address(this))) {
            revert("Did not produce the right amount of token2");
        }
    }

    function testXYKpairNoFeeInvariance(uint256 amountIn) public payable {
        vm.assume(amountIn > 100000 && amountIn < MockERC20(token0).balanceOf(address(this)));

        uint256[] memory path = new uint256[](2);
        path[0] = id010;
        path[1] = id120;

        // First we do a round trip to snap amountIn to a nearby quantity that will be invariant to round trips.
        uint256 amountOutFwd = helios.swap(address(this), path, token0, amountIn);
        uint256 amountOutBack = helios.swap(address(this), id120, token2, amountOutFwd);

        amountOutBack = helios.swap(address(this), id010, token1, amountOutBack);

        uint256 diff = amountIn > amountOutBack ? amountIn - amountOutBack : amountOutBack - amountIn;

        if (diff > 512) {
            revert("more than 512 wei difference from round tripping");
        }

        amountIn = amountOutBack;

        uint256 b0 = MockERC20(token0).balanceOf(address(this));
        uint256 b1 = MockERC20(token1).balanceOf(address(this));
        uint256 b2 = MockERC20(token2).balanceOf(address(this));
        vm.assume(amountIn > 100000 && amountIn < b0);

        amountOutFwd = helios.swap(address(this), path, token0, amountIn);
        amountOutBack = helios.swap(address(this), id120, token2, amountOutFwd);
        amountOutBack = helios.swap(address(this), id010, token1, amountOutBack);

        if (amountIn != amountOutBack) {
            revert("round tripping with 0 fee does not give back original amount");
        }
        if (b0 != MockERC20(token0).balanceOf(address(this))) {
            revert("token 0 balance is messed up");
        }
        if (b1 != MockERC20(token1).balanceOf(address(this))) {
            revert("token 1 balance is messed up");
        }
        if (b2 != MockERC20(token2).balanceOf(address(this))) {
            revert("token 2 balance is messed up");
        }
    }

    function testArb() public {
        uint256[] memory cycle = new uint256[](3);
        cycle[0] = id01;
        cycle[1] = id12;
        cycle[2] = id02;
        vm.prank(deployer);
        helios.setArbToken(token0);
        vm.prank(deployer);
        helios.addOpportunity(cycle);
        (cycle[0], cycle[2]) = (cycle[2], cycle[0]);
        vm.prank(deployer);
        helios.addOpportunity(cycle);
        vm.prank(deployer);
        helios.setArbBeneficiary(deployer);
        uint256 b0 = MockERC20(token0).balanceOf(deployer);
        uint256 amountIn = 1_000 ether;
        helios.swap(address(this), id01, token0, amountIn);
        uint256 a0 = MockERC20(token0).balanceOf(deployer);
        require(a0 > b0 + 246 ether, "too little arbed");
        require(a0 < b0 + 247 ether, "too much arbed");
    }
}
