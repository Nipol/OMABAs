// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity ^0.8.13;

import "./IToken.sol";
import "./IERC20.sol";

/**
 * @title   Stablecoin
 * @author  yoonsung.eth
 * @notice  해당 컨트랙트는 총 수량이 변동되는 ERC20 형태를 가지고 있으며, `Mint` 권한과 `Burn` 권한 그리고 이를 부여할 수 있는 `Executor` 권한이
 *          분리되어 있습니다. `Executor` 권한은 `Mint` 또는 `Burn`권한을 가지지 못합니다.
 * @dev     해당 컨트랙트의 Storage는 일반적인 Solidity와 다르게 구성되어 사용자의 `balance`는 별도의 해싱없이 사용자의 공개키에 매핑되어 있으며, 
 *          `allowance`는 `Slot_id + 소유자 주소 + 대리자 주소`로 해싱된 Storage 키에 저장됩니다. 주소별 권한은 `Slot_id + 대상 주소`로 해싱
 *          된 Storage 키에 저장됩니다. TODO: transfer가 Zero Address로 갈 경우, revert? false? 하여튼 추가 할 것
 */
contract Stablecoin is IToken, IERC20 {
    uint256 constant Slot_Permission = (0x6f);
    uint256 constant Slot_Allowance = (0x7f);
    uint256 constant Slot_TotalSupply = (0x707a13cff1700000000000000000000000000000000000000000000000000000);
    uint256 constant Event_Transfer_Signature = (0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef);
    uint256 constant Event_Approve_Signature = (0x8c5be1e5ebec7d5bd14f71427d1e84f3dd0314c0f7b2291e5b200ac8c7c3b925);

    uint256 constant Error_NotAllowedToCaller = (0x2f50e82d);
    uint256 constant Error_NotPermissioned = (0x7f63bd0f);
    uint256 constant Error_NotAllowedBalance = (0x3df75a2d);
    uint256 constant Error_NotEnoughBalance = (0xad3a8b9e);

    string public constant name = "WAI";
    string public constant symbol = "WAI";
    uint8 public constant decimals = 5;
    string public constant version = "1";

    error NotAllowedToCaller();
    error NotPermissioned();
    error NotAllowedBalance();
    error NotEnoughBalance();

    constructor() {
        assembly {
            mstore(0x80, caller())
            mstore8(0x80, Slot_Permission)
            sstore(keccak256(0x80, 0x20), 0x4)
        }
    }

    /**
     * @notice  `toPermission`의 토큰 생성 권한을 이전 상태의 반대로 돌립니다. 권한이 있었다면 없어지며, 없었다면 권한이 생깁니다.
     * @param   toPermission 대상 주소
     */
    function toggleMint(address toPermission) external {
        assembly {
            if eq(toPermission, caller()) { 
                mstore(0x0, Error_NotAllowedToCaller)
                revert(0x1c, 0x4)
            }

            mstore(0x80, caller())
            mstore8(0x80, Slot_Permission)
            if iszero(and(sload(keccak256(0x80, 0x20)), 0x4)) { 
                mstore(0x0, Error_NotPermissioned)
                revert(0x1c, 0x4)
            }

            mstore(0x80, toPermission)
            mstore8(0x80, Slot_Permission)
            sstore(keccak256(0x80, 0x20), xor(sload(keccak256(0x80, 0x20)), 0x1))
        }
    }

    /**
     * @notice  `toPermission`의 토큰 소각 권한을 이전 상태의 반대로 돌립니다. 권한이 있었다면 없어지며, 없었다면 권한이 생깁니다.
     * @param   toPermission 대상 주소
     */
    function toggleBurn(address toPermission) external {
        assembly {
            if eq(toPermission, caller()) { 
                mstore(0x0, Error_NotAllowedToCaller)
                revert(0x1c, 0x4)
            }

            mstore(0x80, caller())
            mstore8(0x80, Slot_Permission)
            if iszero(and(sload(keccak256(0x80, 0x20)), 0x4)) { 
                mstore(0x0, Error_NotPermissioned)
                revert(0x1c, 0x4)
            }

            mstore(0x80, toPermission)
            mstore8(0x80, Slot_Permission)
            sstore(keccak256(0x80, 0x20), xor(sload(keccak256(0x80, 0x20)), 0x2))
        }
    }

    /**
     * @notice  `to`에게 `amount`만큼 토큰을 생성하는 함수
     * @dev     `Mint` 권한을 가진 사용자만 이를 수행할 수 있습니다.
     * @param   to      대상 주소
     * @param   amount  생성 수량
     */
    function mint(address to, uint256 amount) external {
        assembly {
            mstore(0x80, caller())
            mstore8(0x80, Slot_Permission)
            if iszero(and(sload(keccak256(0x80, 0x20)), 0x1)) { 
                mstore(0x0, Error_NotPermissioned)
                revert(0x1c, 0x4)
            }

            sstore(to, add(sload(to), amount))
            sstore(Slot_TotalSupply, add(sload(Slot_TotalSupply), amount))

            mstore(0x80, amount)
            log3(0x80, 0x20, Event_Transfer_Signature, 0x0, to)
        }
    }

    /**
     * @notice  `from`으로 부터 `amount`만큼 토큰을 소각하는 함수
     * @dev     `Burn` 권한을 가진 사용자만 이를 수행할 수 있으며, `Burn` 권한을 가진 사용자에게 토큰 사용을 허락하여야 수행됩니다.
     * @param   from    대상 주소
     * @param   amount  생성 수량
     */
    function burn(address from, uint256 amount) external {
        assembly {
            // 호출자가 burn이 가능한 권한을 가지고 있는지 확인
            mstore(0x80, caller())
            mstore8(0x80, Slot_Permission)
            if iszero(and(sload(keccak256(0x80, 0x20)), 0x2)) { 
                mstore(0x0, Error_NotPermissioned)
                revert(0x1c, 0x4)
            }

            // approve 체크, 및 삭감
            mstore(0x80, from)
            mstore8(0x80, Slot_Allowance)
            mstore(0xa0, caller())
            let storageKey := keccak256(0x80, 0x40)
            mstore(0x80, sload(storageKey))
            if iszero(iszero(lt(mload(0x80), amount))) { 
                mstore(0x0, Error_NotAllowedBalance)
                revert(0x1c, 0x4)
            }
            sstore(storageKey, sub(sload(storageKey), amount))

            // 밸런스 체크 및 삭감
            mstore(0x80, sload(from))
            if iszero(iszero(lt(mload(0x80), amount))) { 
                mstore(0x0, Error_NotEnoughBalance)
                revert(0x1c, 0x4)
            }
            sstore(from, sub(sload(from), amount))

            // 총 수량 줄임
            sstore(Slot_TotalSupply, sub(sload(Slot_TotalSupply), amount))

            mstore(0x80, amount)
            log3(0x80, 0x20, Event_Transfer_Signature, from, 0x0)
        }
    }

    /**
     * @notice  `spender`에게 `amount`만큼 토큰 사용을 허용하는 함수
     * @param   spender 대상 주소
     * @param   amount  허용할 수량
     */
    function approve(address spender, uint256 amount) external returns (bool success) {
        assembly {
            mstore(0x80, caller())
            mstore8(0x80, Slot_Allowance)
            mstore(0xa0, spender)
            sstore(keccak256(0x80, 0x40), amount)

            mstore(0x80, amount)
            log3(0x80, 0x20, Event_Approve_Signature, caller(), spender)
            success := 0x1
        }
    }

    /**
     * @notice  `to`에게 `amount`만큼 토큰을 전송합니다.
     * @param   to      대상이 되는 주소
     * @param   amount  전송할 토큰 수량
     */
    function transfer(address to, uint256 amount) external returns (bool success) {
        assembly {
            mstore(0x80, sload(caller()))
            if iszero(iszero(lt(mload(0x80), amount))) {
                mstore(0x0, Error_NotEnoughBalance)
                revert(0x1c, 0x4)
            }

            sstore(caller(), sub(mload(0x80), amount))
            sstore(to, add(sload(to), amount))

            mstore(0x80, amount)
            log3(0x80, 0x20, Event_Transfer_Signature, caller(), to)
            success := 0x1
        }
    }

    /**
     * @notice  토큰 사용이 허용된 제 3자가, `from`이 `to`에게 `amount`만큼 토큰을 전송하도록 합니다.
     * @param   from    토큰을 전송할 주체
     * @param   to      대상이 되는 주소
     * @param   amount  전송할 토큰 수량
     */
    function transferFrom(address from, address to, uint256 amount) external returns (bool success) {
        assembly {
            // 호출자의 Allowance 확인
            mstore(0x80, from)
            mstore8(0x80, Slot_Allowance)
            mstore(0xa0, caller())
            let storageKey := keccak256(0x80, 0x40)
            mstore(0xc0, sload(storageKey))
            if iszero(iszero(lt(mload(0xc0), amount))) {
                mstore(0x0, Error_NotAllowedBalance)
                revert(0x1c, 0x4)
            }
            sstore(storageKey, sub(mload(0xc0), amount))

            // from의 밸런스 확인
            mstore(0x80, sload(from))
            if iszero(iszero(lt(mload(0x80), amount))) {
                mstore(0x0, Error_NotEnoughBalance)
                revert(0x1c, 0x4)
            }
            sstore(from, sub(sload(from), amount))

            // to의 밸런스 증가
            sstore(to, add(sload(to), amount))

            mstore(0x80, amount)
            log3(0x80, 0x20, Event_Transfer_Signature, from, to)
            success := 0x1
        }
    }

    /**
     * @notice  `to`의 현재 권한을 반환
     * @param   to 권한을 확인할 대상 주소
     */
    function getPermission(address to) external view returns (uint256) {
        assembly {
            mstore(0x80, to)
            mstore8(0x80, Slot_Permission)
            mstore(0x80, sload(keccak256(0x80, 0x20)))
            return(0x80, 0x20)
        }
    }

    /**
     * @notice  현재 발행된 모든 토큰의 총량을 반환
     */
    function totalSupply() public view returns (uint256) {
        assembly {
            mstore(0x80, sload(Slot_TotalSupply))
            return(0x80, 0x20)
        }
    }

    /**
     * @notice  `owner`가 소유중인 토큰 수량 반환
     * @param   owner 대상 주소
     */
    function balanceOf(address owner) external view returns (uint256) {
        assembly {
            mstore(0x80, sload(owner))
            return(0x80, 0x20)
        }
    }

    /**
     * @notice  `owner`가 `spender`에게 허용한 토큰의 수량
     * @param   owner   토큰 소유자 주소
     * @param   spender 대리자 주소
     */
    function allowance(address owner, address spender) external view returns (uint256) {
        assembly {
            mstore(0x80, owner)
            mstore8(0x80, Slot_Allowance)
            mstore(0xa0, spender)
            mstore(0x80, sload(keccak256(0x80, 0x40)))
            return(0x80, 0x20)
        }
    }
}
