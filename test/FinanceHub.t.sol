// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/FinanceHub.sol";
import "../src/IFFF.sol";
import "../src/TickMath.sol";
import "../src/Math.sol";
import "../src/Stablecoin.sol";

import "./FFFM.sol";

abstract contract FinanceHubBed is Test {
    event NewCollateral(
        bytes32 indexed CollateralId,
        address priceFeed,
        address token,
        uint256 ratioLimit,
        uint256 borrowLimit,
        uint256 current
    );

    //0% for base
    //base=$(bc -l <<< "scale=27; e( l(1.5 / 100 + 1)/(60 * 60 * 24 * 365)) * 10^27")
    //base=$(bc -l <<< "${base} - 10^27")
    //echo ${base%.*}
    uint256 constant baseRate = 0;

    //0% for 1 Minute
    //bc -l <<< 'scale=27; e( l(1.01)/(60 * 60 * 24 * 365) )'
    //bc -l <<< 'scale=27; e( l(1.01)/(60) )'
    uint256 constant annualRate = 1000165852599574676181767704;
    Stablecoin public c;
    Stablecoin public erc20;
    FFFM public ETHfff;
    FFFM public GEMfff;
    FinanceHub public w;

    function setUp() public virtual {
        ETHfff = new FFFM(int24(-152327));
        GEMfff = new FFFM(int24(-152327));
        c = new Stablecoin();
        erc20 = new Stablecoin();
        w = new FinanceHub(baseRate, address(c));
        c.toggleMint(address(w));
        c.toggleBurn(address(w));
        erc20.toggleMint(Address("Minter"));
        erc20.toggleBurn(Address("Burner"));
        c.approve(address(w), type(uint256).max);
    }

    //---------------------------------------------------//
    // Test case Helper area
    //---------------------------------------------------//
    function Address(string memory name) internal returns (address ret) {
        ret = address(uint160(uint256(keccak256(abi.encode(name)))));
        vm.label(ret, name);
    }

    /**
     * @notice 프라이스 피드의 동작 테스트
     */
    // function testPriceFeed() public {
    //     vm.createSelectFork(vm.rpcUrl("SEPOLIA_RPC_URL"));
    //     try IFFF(address(0xb0910E7C7AdEC52eF3Bae5DB9D01fd967A22fb7b)).consultWithSeconds(600) returns (
    //         int24 arithmeticMeanTick, uint128 harmonicMeanLiquidity
    //     ) {
    //         console.logInt(arithmeticMeanTick);
    //         uint160 sqrtPrice = TickMath.getSqrtRatioAtTick(arithmeticMeanTick);
    //         uint256 averagePrice = Math.mulDiv(uint256(sqrtPrice) * uint256(sqrtPrice), 10 ** 18, 1 << 192);
    //         console.log(averagePrice);
    //     } catch {
    //         (uint16 frameIndex, uint16 frameCardinality,,) =
    //             IFFF(address(0xb0910E7C7AdEC52eF3Bae5DB9D01fd967A22fb7b)).slot0();
    //         (uint32 blockTimestamp, int56 averageTickCumulative, uint160 secondsPerVolumeCumulativeX128) =
    //             IFFF(address(0xb0910E7C7AdEC52eF3Bae5DB9D01fd967A22fb7b)).frames(frameIndex);
    //         console.log("blockTimestamp ", blockTimestamp);
    //         console.logInt(averageTickCumulative);
    //         console.log(secondsPerVolumeCumulativeX128);
    //         if (frameIndex == 0) {
    //             (blockTimestamp, averageTickCumulative, secondsPerVolumeCumulativeX128) =
    //                 IFFF(address(0xb0910E7C7AdEC52eF3Bae5DB9D01fd967A22fb7b)).frames(frameCardinality);
    //         } else {
    //             (blockTimestamp, averageTickCumulative, secondsPerVolumeCumulativeX128) =
    //                 IFFF(address(0xb0910E7C7AdEC52eF3Bae5DB9D01fd967A22fb7b)).frames(frameIndex - 1);
    //         }
    //         console.log("blockTimestamp ", blockTimestamp);
    //         console.logInt(averageTickCumulative);
    //         console.log(secondsPerVolumeCumulativeX128);
    //     }
    // }

    /**
     * @notice 해당 컨트랙트가 테스트 주체이기 때문에, ETH 받을 수 있도록
     */
    receive() external payable {}
}

/**
 * @title FinanceHubTest
 * @notice
 * @dev Price Feed의 업데이트 주기가 대체로, 현재 시점으로 부터 10분 전 가격을 가져오기 때문에 시간을 넘나드는 테스트를 필요로 하는 경우에 며칠씩 이동하는
 *      것은 현실적이지 않다. 그렇기 때문에 초당 이자율을 적용하여 결과를 빨리 확인하는 방식으로 테스트 코드를 작성해야 합니다.
 */
contract FinanceHubDeplyed is FinanceHubBed {
    function setUp() public override {
        super.setUp();
    }

    /**
     * @notice ETH 담보 정보 추가 테스트
     */
    function testAddCollateralTypeThroughETH() public {
        vm.expectEmit(true, false, false, false);
        emit NewCollateral(bytes32(0), address(ETHfff), address(0), 1_200000000000000000, 10000e5 * 1e27, annualRate);
        // ETH 담보 추가
        bytes32 collateralId = w.addCollateralType(
            // Price Feed Contract
            address(ETHfff),
            // ETH 이므로, Token Contract 주소는 없음
            address(0),
            // 120%
            1_200000000000000000,
            // 최소 대출
            10000e5 * 1e27,
            // 초 단위로 환산한 연간 이자율
            annualRate
        );

        // 추가된 담보 정보 확인
        (
            IFFF priceFeed,
            IERC20 token,
            uint256 ratioLimit,
            uint256 borrowLimit,
            uint256 currentRate,
            uint256 latestTimestamp
        ) = w.CollateralInfos(collateralId);

        assertEq(address(priceFeed), address(ETHfff));
        assertEq(address(token), address(0));
        assertEq(ratioLimit, 1_200000000000000000);
        assertEq(borrowLimit, 10000e5 * 1e27);
        assertEq(currentRate, annualRate);
        assertEq(latestTimestamp, block.timestamp);

        uint256 accumulateRate = w.AccumulateRate(collateralId);
        assertEq(accumulateRate, annualRate);
    }

    /**
     * @notice ERC20 담보 정보 추가 테스트
     */
    function testAddCollateralTypeThroughToken() public {
        vm.expectEmit(true, false, false, false);
        emit NewCollateral(
            keccak256(abi.encodePacked(address(erc20))),
            address(GEMfff),
            address(erc20),
            1_400000000000000000,
            100000e5 * 1e27,
            annualRate
        );
        // ERC20 담보 추가
        bytes32 collateralId = w.addCollateralType(
            // Price Feed Contract
            address(GEMfff),
            // ERC20 토큰 주소
            address(erc20),
            // 140%
            1_400000000000000000,
            // 최소 대출
            100000e5 * 1e27,
            // 초 단위로 환산한 연간 이자율
            annualRate
        );

        assertEq(collateralId, keccak256(abi.encodePacked(address(erc20))));

        // 추가된 담보 정보 확인
        (
            IFFF priceFeed,
            IERC20 token,
            uint256 ratioLimit,
            uint256 borrowLimit,
            uint256 currentRate,
            uint256 latestTimestamp
        ) = w.CollateralInfos(collateralId);

        assertEq(address(priceFeed), address(GEMfff));
        assertEq(address(token), address(erc20));
        assertEq(ratioLimit, 1_400000000000000000);
        assertEq(borrowLimit, 100000e5 * 1e27);
        assertEq(currentRate, annualRate);
        assertEq(latestTimestamp, block.timestamp);

        uint256 accumulateRate = w.AccumulateRate(collateralId);
        assertEq(accumulateRate, annualRate);
    }

    // 추가되지 않은 담보 정보 ETH 유동성 등록
    function testAddNotInitializedETHCollateral() public {
        vm.expectRevert(bytes4(keccak256("NotInitialzedCollateral()")));
        w.addLiquidity{value: 1e18}();
    }

    // 추가되지 않은 담보 정보 토큰 유동성 등록
    function testAddNotInitializedERC20Collateral() public {
        vm.expectRevert(bytes4(keccak256("NotInitialzedCollateral()")));
        w.addLiquidity(bytes32("asdf"), 1e18);
    }

    // 추가되지 않은 ETH 담보 제거
    function testRemoveNotInitializedETHCollateral() public {
        vm.expectRevert(bytes4(keccak256("NotInitialzedCollateral()")));
        w.removeLiquidity(1e18);
    }

    // 추가되지 않은 ERC20 담보 제거
    function testRemoveNotInitializedERC20Collateral() public {
        vm.expectRevert(bytes4(keccak256("NotInitialzedCollateral()")));
        w.removeLiquidity(bytes32("asdf"), 1e18);
    }

    // 추가되지 않은 담보에 대한 토큰 대출
    function testDrawNotInitializedCollateral() public {
        vm.expectRevert(bytes4(keccak256("NotInitialzedCollateral()")));
        w.draw(bytes32("asdf"), 1e18);
    }

    // 추가되지 않은 담보 정보에 대한 회수
    function testRepayNotInitializedCollateral() public {
        vm.expectRevert(bytes4(keccak256("NotInitialzedCollateral()")));
        w.repay(bytes32("asdf"));
    }
}

/**
 * @notice ETH 담보 정보 추가된 상태
 */
contract FinanceHubAddedETHCollateral is FinanceHubBed {
    bytes32 collateralId;

    function setUp() public override {
        super.setUp();
        // ETH 담보 추가
        collateralId = w.addCollateralType(
            // Price Feed Contract
            address(ETHfff),
            // ETH 이므로, Token Contract 주소는 없음
            address(0),
            // 120%
            1_200000000000000000,
            // 최소 대출
            10000e5 * 1e27,
            // 초 단위로 환산한 연간 이자율
            annualRate
        );
    }

    // ETH 담보 추가
    function testAddLiquidity() public {
        w.addLiquidity{value: 1e18}();

        // 개인의 Vault 상태 확인
        (, uint256 collateral, uint256 idebt, uint256 debt) = w.Vaults(address(this), collateralId);
        assertEq(collateral, 1e18);
        assertEq(idebt, 0);
        assertEq(debt, 0);

        // 글로벌 Vault 상태 확인
        (, collateral, idebt, debt) = w.VaultsStatus(collateralId);
        assertEq(collateral, 1e18);
        assertEq(idebt, 0);
        assertEq(debt, 0);
    }

    // ETH 담보 추가 후 담보 제거
    function testRemoveLiquidity() public {
        w.addLiquidity{value: 1e18}();

        uint256 balance = address(this).balance;

        w.removeLiquidity(1e18);

        assertEq(address(this).balance, balance + 1e18);

        // 개인의 Vault 상태 확인
        (, uint256 collateral, uint256 idebt, uint256 debt) = w.Vaults(address(this), collateralId);
        assertEq(collateral, 0);
        assertEq(idebt, 0);
        assertEq(debt, 0);

        // 글로벌 Vault 상태 확인
        (, collateral, idebt, debt) = w.VaultsStatus(collateralId);
        assertEq(collateral, 0);
        assertEq(idebt, 0);
        assertEq(debt, 0);
    }
}

/**
 * @notice ERC20 담보물 정보 추가
 */
contract FinanceHubAddedERC20Collateral is FinanceHubBed {
    bytes32 collateralId;

    function setUp() public override {
        super.setUp();
        // ERC20 담보 추가
        collateralId = w.addCollateralType(
            // Price Feed Contract
            address(GEMfff),
            // ERC20
            address(erc20),
            // 140%
            1_400000000000000000,
            // 최소 대출 금액
            100000e5 * 1e27,
            // 초 단위로 환산한 연간 이자율
            annualRate
        );

        vm.prank(Address("Minter"));
        erc20.mint(address(this), 1e18);
        erc20.approve(address(w), type(uint256).max);
    }

    // ERC20 담보물 추가
    function testAddLiquidity() public {
        assertEq(erc20.balanceOf(address(this)), 1e18);

        w.addLiquidity(collateralId, 1e18);

        assertEq(erc20.balanceOf(address(this)), 0);
        assertEq(erc20.balanceOf(address(w)), 1e18);

        // 개인의 Vault 상태 확인
        (, uint256 collateral, uint256 idebt, uint256 debt) = w.Vaults(address(this), collateralId);
        assertEq(collateral, 1e18);
        assertEq(idebt, 0);
        assertEq(debt, 0);

        // 글로벌 Vault 상태 확인
        (, collateral, idebt, debt) = w.VaultsStatus(collateralId);
        assertEq(collateral, 1e18);
        assertEq(idebt, 0);
        assertEq(debt, 0);
    }

    // ERC20 담보물 제거
    function testRemoveLiquidity() public {
        assertEq(erc20.balanceOf(address(this)), 1e18);
        w.addLiquidity(collateralId, 1e18);

        assertEq(erc20.balanceOf(address(w)), 1e18);

        w.removeLiquidity(collateralId, 1e18);
        assertEq(erc20.balanceOf(address(this)), 1e18);

        // 개인의 Vault 상태 확인
        (, uint256 collateral, uint256 idebt, uint256 debt) = w.Vaults(address(this), collateralId);
        assertEq(collateral, 0);
        assertEq(idebt, 0);
        assertEq(debt, 0);

        // 글로벌 Vault 상태 확인
        (, collateral, idebt, debt) = w.VaultsStatus(collateralId);
        assertEq(collateral, 0);
        assertEq(idebt, 0);
        assertEq(debt, 0);
    }
}

abstract contract AddedAllCollateralBed is FinanceHubBed {
    bytes32 public collateralId;

    function setUp() public override virtual {
        super.setUp();
        // ETH 담보 정보
        w.addCollateralType(
            // Price Feed Contract
            address(ETHfff),
            // ETH 이므로, Token Contract 주소는 없음
            address(0),
            // 120%
            1_200000000000000000,
            // 최소 대출
            10000e5 * 1e27,
            // 초 단위로 환산한 연간 이자율
            annualRate
        );

        // ERC20 담보 정보 등록
        collateralId = w.addCollateralType(
            // Price Feed Contract
            address(GEMfff),
            // Token Contract 주소
            address(erc20),
            // 140%
            1_400000000000000000,
            // 최소 대출 금액
            100000e5 * 1e27,
            // 초 단위로 환산한 연간 이자율
            annualRate
        );

        vm.prank(Address("Minter"));
        erc20.mint(address(this), 1e18);
        erc20.approve(address(w), type(uint256).max);

        w.addLiquidity{value: 1e18}();
        w.addLiquidity(collateralId, 1e18);
    }
}

contract DrawTest is AddedAllCollateralBed {
    // 이더 담보물에서 대출
    function testDrawFromETHCollateral() public {
        w.draw(bytes32(0), 100000e5);
        assertEq(c.balanceOf(address(this)), 100000e5);
    }

    // 이더 담보물에서 0개 대출
    function testDrawZero() public {
        vm.expectRevert(bytes4(keccak256("NotAllowedZeroAmount()")));
        w.draw(bytes32(0), 0);
        assertEq(c.balanceOf(address(this)), 0);
    }

    // 이더 담보물에서, 담보 비율보다 많은 금액 대출
    function testOverDraw() public {
        vm.expectRevert(bytes4(keccak256("ReachForTheSky()")));
        w.draw(bytes32(0), 2200000e5);
        assertEq(c.balanceOf(address(this)), 0);
    }

    // 최소 대출 금액보다 적은 금액 대출
    function testSmallDraw() public {
        vm.expectRevert(bytes4(keccak256("OverLimit()")));
        w.draw(bytes32(0), 9000e5);
        assertEq(c.balanceOf(address(this)), 0);
    }

    // 대출 이후, 비율을 넘지 않는 선에서 담보물 회수
    function testDrawAndRemoveCollateral() public {
        w.draw(bytes32(0), 1000000e5);
        assertEq(c.balanceOf(address(this)), 1000000e5);
        w.removeLiquidity(0.5 ether);
        assertEq(address(w).balance, 0.5 ether);
    }

    // 대출 이후, 비율을 넘는 수준의 담보물 회수
    function testDrawAndRemoveCollateralReachToLimit() public {
        w.draw(bytes32(0), 1000000e5);
        assertEq(c.balanceOf(address(this)), 1000000e5);
        vm.expectRevert(bytes4(keccak256("ReachForTheSky()")));
        w.removeLiquidity(0.8 ether);
    }

    // 대출 이후 실제 예치된 금액보다 더 많은 금액 출금
    function testDrawAndOverRemoveCollateral() public {
        w.draw(bytes32(0), 1000000e5);
        assertEq(c.balanceOf(address(this)), 1000000e5);
        vm.expectRevert(bytes4(keccak256("RemoveOverAmount()")));
        w.removeLiquidity(1.1 ether);
    }
}

abstract contract DrawedFromHubBed is AddedAllCollateralBed {
    function setUp() public override {
        super.setUp();
        w.draw(bytes32(0),  1000000e5);
        w.draw(collateralId, 700000e5);
        vm.warp(block.timestamp + 1);
    }
}

contract RepayTest is DrawedFromHubBed {
    function testRepayWithAmounts() public {
        w.repay(bytes32(0), 1000000e5);
        (, uint256 collateral, uint256 actualDebt, uint256 debt) = w.Vaults(address(this), bytes32(0));

        w.repay(bytes32(0), 16588011); // 순간 미 반영 이자도 포함
        (, collateral, actualDebt, debt) = w.Vaults(address(this), bytes32(0));
    }

    function testRepayAll() public {
        w.repay(bytes32(0));
        (, uint256 collateral, uint256 actualDebt, uint256 debt) = w.Vaults(address(this), bytes32(0));
    }

    function testRepayWithNotEnoughBalance() public {
        c.transfer(address(0), c.balanceOf(address(this)));

        vm.expectRevert(bytes4(keccak256("NotEnoughBalance()")));
        w.repay(bytes32(0), 1000000e5);
    }

    function testRepayAllWithNotEnoughBalance() public {
        c.transfer(address(0), c.balanceOf(address(this)));

        vm.expectRevert(bytes4(keccak256("NotEnoughBalance()")));
        w.repay(bytes32(0));
    }

    function testRepayWithZeroAmount() public {
        vm.expectRevert(bytes4(keccak256("NotAllowedZeroAmount()")));
        w.repay(bytes32(0), 0);
    }
}