/**
 * SPDX-License-Identifier: LGPL-3.0-or-later
 */

pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {Stablecoin, IERC20} from "../src/Stablecoin.sol";

contract StablecoinTest is Test {
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    Stablecoin token;
    string private name = "WAI";
    string private symbol = "WAI";
    uint8 private decimals = 5;
    string private version = "1";

    //---------------------------------------------------//
    // Test case Helper area
    //---------------------------------------------------//
    function Address(string memory n) internal returns (address ret) {
        ret = address(uint160(uint256(keccak256(abi.encode(n)))));
        vm.label(ret, n);
    }

    //---------------------------------------------------//
    // Test case Setup Area
    //---------------------------------------------------//
    function setUp() public {
        token = new Stablecoin();
        token.toggleMint(Address("Minter"));
        token.toggleBurn(Address("Burner"));
    }

    //---------------------------------------------------//
    // Test cases
    //---------------------------------------------------//
    /**
     * @notice 초기 메타데이터들의 정합성을 검사합니다.
     */
    function testInitialMetadata() public {
        assertEq(token.name(), name);
        assertEq(token.symbol(), symbol);
        assertEq(token.decimals(), decimals);
        assertEq(token.version(), version);
    }

    /**
     * @notice 토큰 생성 권한 토글링 테스트
     */
    function testToggleMintPermission() public {
        token.toggleMint(Address("Alice"));
        assertEq(token.getPermission(Address("Alice")), 1);
        token.toggleMint(Address("Alice"));
        assertEq(token.getPermission(Address("Alice")), 0);
    }

    /**
     * @notice 토큰 소각 권한 토글링 테스트
     */
    function testToggleBurnPermission() public {
        token.toggleBurn(Address("Alice"));
        assertEq(token.getPermission(Address("Alice")), 2);
        token.toggleBurn(Address("Alice"));
        assertEq(token.getPermission(Address("Alice")), 0);
    }

    /**
     * @notice 토큰 권한이 없는 주소가 토큰 권한 요청 테스트
     */
    function testTogglePermissionNotFromExecutor() public {
        vm.prank(Address("Alice"));
        vm.expectRevert(bytes4(keccak256("NotPermissioned()")));
        token.toggleBurn(Address("Bob"));

        vm.prank(Address("Alice"));
        vm.expectRevert(bytes4(keccak256("NotPermissioned()")));
        token.toggleMint(Address("Bob"));
    }

    /**
     * @notice Executor가 자신에게 Mint와 Burn 권한 요청
     */
    function testTogglePermissionToSelf() public {
        vm.expectRevert(bytes4(keccak256("NotAllowedToCaller()")));
        token.toggleMint(address(this));
        vm.expectRevert(bytes4(keccak256("NotAllowedToCaller()")));
        token.toggleBurn(address(this));
    }

    /**
     * @notice 토큰 권한을 섞어서 부여
     */
    function testTogglePermissionComplex() public {
        token.toggleMint(Address("Alice"));
        assertEq(token.getPermission(Address("Alice")), 1);
        token.toggleBurn(Address("Alice"));
        assertEq(token.getPermission(Address("Alice")), 3);
        token.toggleMint(Address("Alice"));
        assertEq(token.getPermission(Address("Alice")), 2);
        token.toggleBurn(Address("Alice"));
        assertEq(token.getPermission(Address("Alice")), 0);
    }

    /**
     * @notice `mint`함수 테스트, 권한 있는 주소가 호출
     */
    function testMintAmount() public {
        vm.prank(Address("Minter"));
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(0), address(this), 100e18);
        token.mint(address(this), 100e18);
        assertEq(token.totalSupply(), 100e18);
        assertEq(token.balanceOf(address(this)), 100e18);
    }

    /**
     * @notice 토큰 컨트랙트의 소유자가 아닌 주소의 호출
     */
    function testMintAndBurnFromNotPermissioned() public {
        vm.expectRevert(bytes4(keccak256("NotPermissioned()")));
        token.mint(Address("alice"), 1e18);

        vm.expectRevert(bytes4(keccak256("NotPermissioned()")));
        token.burn(Address("alice"), 1e18);
    }

    /**
     * @notice `burn` 함수 테스트
     */
    function testBurnTheToken() public {
        // 100개 생성
        vm.prank(Address("Minter"));
        token.mint(address(this), 100e18);
        assertEq(token.balanceOf(address(this)), 100e18);
        // 토큰 소각 허용
        token.approve(Address("Burner"), 1e18);
        // 토큰 소각
        vm.prank(Address("Burner"));
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(this), address(0), 1e18);
        token.burn(address(this), 1e18);
        assertEq(token.balanceOf(address(this)), 99e18);
    }

    /**
     * @notice `burn` 함수 테스트, 수량 없음
     */
    function testBurnWithNotEnoughBalance() public {
        // 토큰 소각 허용
        vm.expectEmit(true, true, false, true);
        emit Approval(address(this), Address("Burner"), 1e18);
        token.approve(Address("Burner"), 1e18);

        vm.prank(Address("Burner"));
        vm.expectRevert(bytes4(keccak256("NotEnoughBalance()")));
        token.burn(address(this), 1e18);
    }

    /**
     * @notice `burn` 함수 테스트, 밸런스 허용되지 않음
     */
    function testBurnWithNotApproved() public {
        vm.prank(Address("Burner"));
        vm.expectRevert(bytes4(keccak256("NotAllowedBalance()")));
        token.burn(address(this), 1e18);
    }

    /**
     * @notice `burn` 함수 테스트, 권한 없음
     */
    function testBurnFromNotPermissioned() public {
        vm.expectRevert(bytes4(keccak256("NotPermissioned()")));
        token.burn(address(this), 1e18);
    }

    /**
     * @notice `tranfer`함수의 일반적인 전송 테스트
     */
    function testTransfer() public {
        vm.prank(Address("Minter"));
        token.mint(address(this), 100e18);
        assertEq(token.totalSupply(), 100e18);
        assertEq(token.balanceOf(address(this)), 100e18);
        assertEq(token.balanceOf(address(10)), 0);

        vm.expectEmit(true, true, false, true);
        emit Transfer(address(this), address(10), 100e18);
        token.transfer(address(10), 100e18);
        assertEq(token.totalSupply(), 100e18);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(10)), 100e18);
    }

    function testNoneApprovedTransferFrom() public {
        vm.prank(Address("Minter"));
        token.mint(address(10), 100e18);
        vm.expectRevert(bytes4(keccak256("NotAllowedBalance()")));
        token.transferFrom(address(10), address(this), 100e18);
    }

    function testApprovedTransferFrom() public {
        vm.prank(Address("Minter"));
        token.mint(address(10), 100e18);
        vm.prank(address(10));
        token.approve(address(this), 100e18);
        assertEq(token.allowance(address(10), address(this)), 100e18);

        vm.expectEmit(true, true, false, true);
        emit Transfer(address(10), address(this), 100e18);
        token.transferFrom(address(10), address(this), 100e18);
        assertEq(token.balanceOf(address(this)), 100e18);
        assertEq(token.allowance(address(10), address(this)), 0);
    }

    function testApprovedTransferFromOverBalance() public {
        vm.prank(Address("Minter"));
        token.mint(address(10), 100e18);
        vm.prank(address(10));
        token.approve(address(this), 100e18);
        assertEq(token.allowance(address(10), address(this)), 100e18);
        vm.expectRevert(bytes4(keccak256("NotAllowedBalance()")));
        token.transferFrom(address(10), address(this), 101e18);
    }

    function testTransferOverBalance() public {
        assertEq(token.totalSupply(), 0);
        assertEq(token.balanceOf(address(this)), 0);
        vm.expectRevert(bytes4(keccak256("NotEnoughBalance()")));
        token.transfer(address(10), 1);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(10)), 0);
    }
}
