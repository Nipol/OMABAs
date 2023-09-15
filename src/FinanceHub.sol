// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity ^0.8.13;

import "./Math.sol";
import "./TickMath.sol";
import "./IFFF.sol";
import "./IToken.sol";
import "./IERC20.sol";

error RemoveOverAmount();
error OverLimit();
error ReachForTheSky();
error NotInitialzedCollateral();
error NotAllowedZeroAmount();
error NotEnoughBalance();

/**
 * @title FinanceHub
 * @author yoonsung.eth
 * @notice 해당 컨트랙트는, 담보의 정보 및 자산을 저장하고 사용자들의 부채 현황 및 전체 부채를 추적하며, Stablecoin을 생성하는 주체입니다.
 */
contract FinanceHub {
    event NewCollateral(
        bytes32 indexed CollateralId,
        address priceFeed,
        address token,
        uint256 ratioLimit,
        uint256 borrowLimit,
        uint256 current
    );

    //---------------------------------------------------//
    // DEBT Information area
    //---------------------------------------------------//
    enum VaultState {
        Normal,
        Liquidate
    }

    /**
     * @notice Accounting Struct for User and Global.
     */
    struct Vault {
        // 해당 금고가, 일반적인 상태인지, 청산 중인 상태인지 나타냄.
        VaultState state;
        // 담보의 수량 (1e18)
        uint256 collateral;
        // 실제 대출에 사용된 총 수량 (1e5), Global의 경우 누적된 수수료
        uint256 actualDebt;
        // 이자가 반영된 대출 수량 (1e27)
        uint256 debt;
    }

    // @notice 담보별, 전체 대출 현황
    mapping(bytes32 collateralType => Vault) public VaultsStatus;

    // @notice 담보별, 전체 부채 현황
    mapping(bytes32 collateralType => Vault) public DebtStatus;

    // @notice 사용자들의 대출 현황
    mapping(address => mapping(bytes32 collateralType => Vault)) public Vaults;

    //---------------------------------------------------//
    // Colletral Information area
    //---------------------------------------------------//

    /**
     * @notice 담보물에 대한 모든 정보, TODO: 토큰과 피드 정보는 별도로 접근해야할 필요가 있음.
     */
    struct Collateral {
        // @notice 담보물의 가격 정보를 제공하는 Price Feed 컨트랙트
        IFFF priceFeed;
        // @notice 담보물로 사용될 토큰의 주소
        IERC20 token;
        // @notice 담보 대비 대출 가능 비율
        uint256 ratioLimit; // = 1_200000000000000000 120% (1e18)
        // @notice 최소 대출 금액
        uint256 borrowLimit; // = 10000e5 * 1e27 최소 만원 이상 빌려야 함
        // @notice 현재 연간 수수료 비율
        uint256 currentRate;
        // @notice 마지막으로 이자율을 업데이트 한 시간
        uint256 latestTimestamp;
    }

    // @notice 모든 담보 대출에 사용되는 기본 이자율
    uint256 public Base;

    // @notice 담보의 정보
    mapping(bytes32 collateralType => Collateral) public CollateralInfos;

    // @notice 누적 수수료 비율
    mapping(bytes32 collateralType => uint256) public AccumulateRate;

    // @notice 실제 대출에 사용될 코인
    IERC20 public immutable Stablecoin;

    //---------------------------------------------------//
    // modifier area
    //---------------------------------------------------//

    //---------------------------------------------------//
    // constructor area
    //---------------------------------------------------//

    /**
     * @notice 스테이블 코인 시스템을 초기화 하는 생성자, 기본 이자율, 부채 대상이 되는 것들을
     * @param baseRate      모든 자산에 반영될 기본 이자율
     * @param stablecoin     address 가격 정보를 제공하는 프라이스 피드
     */
    constructor(uint256 baseRate, address stablecoin) {
        Base = baseRate;
        Stablecoin = IERC20(stablecoin);
    }

    //---------------------------------------------------//
    // External Function area
    //---------------------------------------------------//

    /**
     * @notice  새로운 담보 유형 추가
     * @dev     TODO: Only Gov
     * @param   priceFeed       담보의 가격 정보를 제공하는 컨트랙트 주소
     * @param   token           담보로 사용할 토큰 주소
     * @param   ratioLimit      최소 담보비 부채율, eg) 1_200000000000000000 120% (1e18)
     * @param   annualRate      매 초당 적용될 연간 이자율
     * @return  collateralId    담보에 대한 고유 아이디
     */
    function addCollateralType(
        address priceFeed,
        address token,
        uint256 ratioLimit,
        uint256 borrowLimit,
        uint256 annualRate
    ) external returns (bytes32 collateralId) {
        // 새로운 담보 유형 데이터 초기화
        Collateral memory tc = Collateral({
            priceFeed: IFFF(priceFeed),
            token: IERC20(token),
            ratioLimit: ratioLimit,
            borrowLimit: borrowLimit,
            currentRate: annualRate,
            latestTimestamp: block.timestamp
        });

        if (token == address(0)) {
            collateralId = bytes32(0);
        } else {
            // Collateral Id 계산
            collateralId = keccak256(abi.encodePacked(token));
        }

        // 새로운 Collateral 추가
        CollateralInfos[collateralId] = tc;

        // Collateral에 따른 누적 이자율 계산
        AccumulateRate[collateralId] = annualRate;

        emit NewCollateral(collateralId, priceFeed, token, ratioLimit, borrowLimit, annualRate);
    }

    /**
     * @notice 내 포지션에 ETH 유동성을 추가하는 함수
     */
    function addLiquidity() external payable {
        _updateAccumulateFee(bytes32(0));

        // 글로벌 금고 가져오기
        Vault memory gv = VaultsStatus[bytes32(0)];
        // 개인 금고 가져오기
        Vault memory v = Vaults[msg.sender][bytes32(0)];

        v.collateral += msg.value;
        gv.collateral += msg.value;

        Vaults[msg.sender][bytes32(0)] = v;
        VaultsStatus[bytes32(0)] = gv;
    }

    /**
     * @notice 내 포지션에 토큰 유동성을 추가하는 함수
     */
    function addLiquidity(bytes32 collateralId, uint256 amounts) external {
        // ETH 담보와 같으면 실패
        if (collateralId == bytes32(0)) revert();

        _updateAccumulateFee(collateralId);

        // 담보 정보 가져오기
        Collateral memory ci = CollateralInfos[collateralId];

        // 글로벌 금고 가져오기
        Vault memory gv = VaultsStatus[collateralId];
        // 개인 금고 가져오기
        Vault memory v = Vaults[msg.sender][collateralId];

        if (!safeTransferFrom(ci.token, msg.sender, address(this), amounts)) revert();

        v.collateral += amounts;
        gv.collateral += amounts;

        Vaults[msg.sender][collateralId] = v;
        VaultsStatus[collateralId] = gv;
    }

    /**
     * @notice 내 포지션에서 ETH 유동성을 제거하는 함수
     * @dev     대출 비율 확인 되어야 함
     */
    function removeLiquidity(uint256 amounts) external {
        _updateAccumulateFee(bytes32(0));

        // 담보 정보 가져오기
        Collateral memory ci = CollateralInfos[bytes32(0)];
        // 글로벌 금고 가져오기
        Vault memory gv = VaultsStatus[bytes32(0)];
        // 개인 금고 가져오기
        Vault memory v = Vaults[msg.sender][bytes32(0)];

        // 제거하려는 유동성이 더 크면 실패 하여야 함
        if (v.collateral < amounts) revert RemoveOverAmount();

        // 대출이 있는 경우
        if (v.debt != 0) {
            // 담보의 10분 평균 가격 정보 가져오기
            uint256 collateralValue = _getAveragePrice(bytes32(0));

            // 나의 총 담보에서, 출금하려는
            uint256 valuation = Math.mulDiv(v.collateral - amounts, collateralValue, 1e18);

            uint256 ratio = (valuation * 1e45) / v.debt;

            // 대출 비율 확인, 더스트 범퍼 필요.
            if (ratio <= ci.ratioLimit) revert ReachForTheSky();
        }

        v.collateral -= amounts;
        gv.collateral -= amounts;

        Vaults[msg.sender][bytes32(0)] = v;
        VaultsStatus[bytes32(0)] = gv;

        if (!transferETH(msg.sender, amounts)) revert();
    }

    /**
     * @notice 내 포지션에서 토큰 유동성을 제거하는 함수
     */
    function removeLiquidity(bytes32 collateralId, uint256 amounts) external {
        _updateAccumulateFee(collateralId);

        // 담보 정보 가져오기
        Collateral memory ci = CollateralInfos[collateralId];
        // 글로벌 금고 가져오기
        Vault memory gv = VaultsStatus[collateralId];
        // 개인 금고 가져오기
        Vault memory v = Vaults[msg.sender][collateralId];

        // 제거하려는 유동성이 더 크면 실패 하여야 함
        if (v.collateral < amounts) revert RemoveOverAmount();

        // 대출이 있는 경우
        if (v.debt != 0) {
            // 담보의 10분 평균 가격 정보 가져오기
            uint256 collateralValue = _getAveragePrice(collateralId);

            // 나의 총 담보에서, 출금하려는
            uint256 valuation = Math.mulDiv(v.collateral - amounts, collateralValue, 1e18);

            uint256 ratio = (valuation * 1e45) / v.debt;

            // 대출 비율 확인, 더스트 범퍼 필요.
            if (ratio <= ci.ratioLimit) revert ReachForTheSky();
        }

        v.collateral -= amounts;
        gv.collateral -= amounts;

        Vaults[msg.sender][collateralId] = v;
        VaultsStatus[collateralId] = gv;

        // 토큰 전송
        if (!safeTransfer(ci.token, msg.sender, amounts)) revert();
    }

    /**
     * @notice 원하는 수량만큼 부채를 생성하는 함수
     */
    function draw(bytes32 collateralId, uint256 amounts) external {
        // 대출 금액이 0인 경우 실패
        if (amounts == 0) revert NotAllowedZeroAmount();
        // 현재 이자율을 업데이트 하면서, 현재 이자율 가져오기
        uint256 rate = _updateAccumulateFee(collateralId);

        // 담보 정보 가져오기
        Collateral memory ci = CollateralInfos[collateralId];

        // 개인 대출 현황 가져오기
        Vault memory v = Vaults[msg.sender][collateralId];

        // 대출 제한 보다 적게 빌리면 실패
        if ((v.debt + (amounts * rate)) < ci.borrowLimit) revert OverLimit();

        // 글로벌 정보 가져오기
        Vault memory gv = VaultsStatus[collateralId];

        // 담보의 10분 평균 가격 정보 가져오기
        uint256 collateralValue = _getAveragePrice(collateralId);

        // 현재 나의 담보와 가격 정보 곱하기
        uint256 valuation = Math.mulDiv(v.collateral, collateralValue, 1e18);

        // (총 유동성 / 내 대출(1))
        uint256 ratio = ((valuation * 1e45) / (v.debt + (amounts * rate)));

        // 대출 비율 확인,, 범퍼 필요.
        if (ratio <= ci.ratioLimit) revert ReachForTheSky();

        // 사용자 Issue += dtab
        _draw(v, gv, amounts, rate);

        Vaults[msg.sender][collateralId] = v;
        VaultsStatus[collateralId] = gv;

        // 토큰 생성
        safeMint(Stablecoin, msg.sender, amounts);
    }

    /**
     * @notice 입력 금액 만큼 상환하는 함수
     * @dev     금고에 대한 다양한 조건들 추가할 것.
     */
    //(input * RAY) / accumulateRate => dart, 실제 상환되는 금액
    function repay(bytes32 collateralId, uint256 amounts) external {
        // 상환 금액이 0인 경우 실패
        if (amounts == 0) revert NotAllowedZeroAmount();
        // 현재 이자율을 업데이트 하면서, 현재 이자율 가져오기
        uint256 rate = _updateAccumulateFee(collateralId);
        // 사용자 금고 가져오기
        Vault memory v = Vaults[msg.sender][collateralId];
        // 전체 금고 가져오기
        Vault memory gv = VaultsStatus[collateralId];

        _repay(v, gv, amounts, rate);

        Vaults[msg.sender][collateralId] = v;
        VaultsStatus[collateralId] = gv;

        // 토큰 흡수
        if (!safeBurn(Stablecoin, msg.sender, amounts)) revert NotEnoughBalance();
    }

    /**
     * @notice 입력 금액을 지정하지 않고 전액 상환하는 함수
     */
    function repay(bytes32 collateralId) external {
        // 사용자 금고 가져오기
        Vault memory v = Vaults[msg.sender][collateralId];
        // 전체 금고 가져오기
        Vault memory gv = VaultsStatus[collateralId];
        // 현재 이자율을 업데이트 하면서, 현재 이자율 가져오기
        uint256 rate = _updateAccumulateFee(collateralId);
        uint256 rad = (((v.actualDebt * 1e18) * rate) - v.debt);
        uint256 wad = rad / 1e45;
        uint256 amounts = wad = (wad * 1e27) < rad ? wad + 1 : wad;

        _repay(v, gv, amounts, rate);

        Vaults[msg.sender][collateralId] = v;
        VaultsStatus[collateralId] = gv;

        // 토큰 흡수
        if (!safeBurn(Stablecoin, msg.sender, amounts)) revert NotEnoughBalance();
    }

    /**
     * @notice  ETH 유동성을 추가하면서, 원하는 수량만큼 대출하는 함수
     * @param   amounts 대출 하고자 하는 수량
     */
    function addWithDraw(uint256 amounts) external payable {
        // 대출 금액이 0인 경우 실패
        if (amounts == 0) revert NotAllowedZeroAmount();

        // 수수료 업데이트
        uint256 rate = _updateAccumulateFee(bytes32(0));

        // 담보 정보 가져오기
        Collateral memory ci = CollateralInfos[bytes32(0)];
        // 글로벌 금고 가져오기
        Vault memory gv = VaultsStatus[bytes32(0)];
        // 개인 금고 가져오기
        Vault memory v = Vaults[msg.sender][bytes32(0)];

        // 담보물 수량 업데이트
        v.collateral += msg.value;
        gv.collateral += msg.value;

        // 대출 제한 보다 적게 빌리면 실패
        if ((v.debt + (amounts * rate)) < ci.borrowLimit) revert OverLimit();

        // 담보의 10분 평균 가격 정보 가져오기
        uint256 collateralValue = _getAveragePrice(bytes32(0));

        // 현재 나의 담보와 가격 정보 곱하기
        uint256 valuation = Math.mulDiv(v.collateral, collateralValue, 1e18);

        // (총 유동성 / 내 대출(1))
        uint256 ratio = ((valuation * 1e45) / (v.debt + (amounts * rate)));

        // 대출 비율 확인,, 범퍼 필요.
        if (ratio <= ci.ratioLimit) revert ReachForTheSky();

        // 사용자 Issue += dtab
        _draw(v, gv, amounts, rate);

        Vaults[msg.sender][bytes32(0)] = v;
        VaultsStatus[bytes32(0)] = gv;

        // 토큰 생성
        if (!safeMint(Stablecoin, msg.sender, amounts)) revert();
    }

    /**
     * @notice 토큰 유동성을 추가하면서, 원하는 수량만큼 대출하는 함수
     * @param   collateralId    담보의 고유 아이디
     * @param   collateral      담보의 수량
     * @param   amounts         대출 하고자 하는 수량
     */
    function addWithDraw(bytes32 collateralId, uint256 collateral, uint256 amounts) external {
        // ETH 담보와 같으면 실패
        if (collateralId == bytes32(0)) revert();

        // 대출 금액이 0인 경우 실패
        if (amounts == 0) revert();

        // 수수료 업데이트
        uint256 rate = _updateAccumulateFee(collateralId);

        // 담보 정보 가져오기
        Collateral memory ci = CollateralInfos[collateralId];
        // 글로벌 금고 가져오기
        Vault memory gv = VaultsStatus[collateralId];
        // 개인 금고 가져오기
        Vault memory v = Vaults[msg.sender][collateralId];

        if (!safeTransferFrom(ci.token, msg.sender, address(this), collateral)) revert();

        // 담보물 수량 업데이트
        v.collateral += collateral;
        gv.collateral += collateral;

        // 대출 제한 보다 적게 빌리면 실패
        if ((v.debt + (amounts * rate)) < ci.borrowLimit) revert OverLimit();

        // 담보의 10분 평균 가격 정보 가져오기
        uint256 collateralValue = _getAveragePrice(collateralId);

        // 현재 나의 담보와 가격 정보 곱하기
        uint256 valuation = Math.mulDiv(v.collateral, collateralValue, 1e18);

        // (총 유동성 / 내 대출(1))
        uint256 ratio = ((valuation * 1e45) / (v.debt + (amounts * rate)));

        // 대출 비율 확인,, 범퍼 필요.
        if (ratio <= ci.ratioLimit) revert ReachForTheSky();

        // 사용자 Issue += dtab
        _draw(v, gv, amounts, rate);

        Vaults[msg.sender][collateralId] = v;
        VaultsStatus[collateralId] = gv;

        // 토큰 생성
        if (!safeMint(Stablecoin, msg.sender, amounts)) revert();
    }

    /**
     * @notice 입력만큼 대출을 상환하면서, 원하는 수량만큼 ETH 유동성을 제거하는 함수 (어차피 빼는건 MAX빼도 됨)
     */
    function repayAndRemove(uint256 repayAmount, uint256 removeAmounts) external {
        // 상환 금액이 0인 경우 실패
        if (repayAmount == 0) revert();
        // 현재 이자율을 업데이트 하면서, 현재 이자율 가져오기
        uint256 rate = _updateAccumulateFee(bytes32(0));
        // 사용자 금고 가져오기
        Vault memory v = Vaults[msg.sender][bytes32(0)];
        // 전체 금고 가져오기
        Vault memory gv = VaultsStatus[bytes32(0)];

        _repay(v, gv, repayAmount, rate);

        // 토큰 흡수
        if (!safeBurn(Stablecoin, msg.sender, repayAmount)) revert();

        // 제거하려는 유동성이 더 크면 실패 하여야 함
        if (v.collateral < removeAmounts) revert RemoveOverAmount();

        // 대출이 있는 경우
        if (v.debt != 0) {
            // 담보 정보 가져오기
            Collateral memory ci = CollateralInfos[bytes32(0)];

            // 담보의 10분 평균 가격 정보 가져오기
            uint256 collateralValue = _getAveragePrice(bytes32(0));

            // 나의 총 담보에서, 출금하려는
            uint256 valuation = Math.mulDiv(v.collateral - removeAmounts, collateralValue, 1e18);

            //TODO: v.debt 이자율 적용
            uint256 ratio = (valuation * 1e45) / v.debt;

            // 대출 비율 확인, 더스트 범퍼 필요.
            if (ratio <= ci.ratioLimit) revert ReachForTheSky();
        }

        v.collateral -= removeAmounts;
        gv.collateral -= removeAmounts;

        Vaults[msg.sender][bytes32(0)] = v;
        VaultsStatus[bytes32(0)] = gv;

        if (!transferETH(msg.sender, removeAmounts)) revert();
    }

    /**
     * @notice 입력만큼 대출을 상환하면서, 원하는 수량만큼 토큰 유동성을 제거하는 함수 (어차피 빼는건 MAX빼도 됨)
     */
    function repayAndRemove(bytes32 collateralId, uint256 repayAmount, uint256 removeAmounts) external {
        // 상환 금액이 0인 경우 실패
        if (repayAmount == 0) revert();
        // 현재 이자율을 업데이트 하면서, 현재 이자율 가져오기
        uint256 rate = _updateAccumulateFee(collateralId);
        // 사용자 금고 가져오기
        Vault memory v = Vaults[msg.sender][collateralId];
        // 전체 금고 가져오기
        Vault memory gv = VaultsStatus[collateralId];

        _repay(v, gv, repayAmount, rate);

        // 토큰 흡수
        if (!safeBurn(Stablecoin, msg.sender, repayAmount)) revert();

        // 제거하려는 유동성이 더 크면 실패 하여야 함
        if (v.collateral < removeAmounts) revert RemoveOverAmount();

        // 대출이 있는 경우
        if (v.debt != 0) {
            // 담보 정보 가져오기
            Collateral memory ci = CollateralInfos[collateralId];

            // 담보의 10분 평균 가격 정보 가져오기
            uint256 collateralValue = _getAveragePrice(collateralId);

            // 나의 총 담보에서, 출금하려는
            uint256 valuation = Math.mulDiv(v.collateral - removeAmounts, collateralValue, 1e18);

            //TODO: v.debt 이자율 적용
            uint256 ratio = (valuation * 1e45) / v.debt;

            // 대출 비율 확인, 더스트 범퍼 필요.
            if (ratio <= ci.ratioLimit) revert ReachForTheSky();
        }

        v.collateral -= removeAmounts;
        gv.collateral -= removeAmounts;

        Vaults[msg.sender][collateralId] = v;
        VaultsStatus[collateralId] = gv;

        if (!safeTransfer(Stablecoin, msg.sender, removeAmounts)) revert();
    }

    /**
     * @notice 모든 대출을 상환하면서, 원하는 수량만큼 ETH 유동성을 제거하는 함수 (어차피 빼는건 MAX빼도 됨)
     */
    function repayAndRemove(uint256 removeAmounts) external {
        // 사용자 금고 가져오기
        Vault memory v = Vaults[msg.sender][bytes32(0)];
        // 전체 금고 가져오기
        Vault memory gv = VaultsStatus[bytes32(0)];
        // 현재 이자율을 업데이트 하면서, 현재 이자율 가져오기
        uint256 rate = _updateAccumulateFee(bytes32(0));
        uint256 rad = (((v.actualDebt * 1e18) * rate) - v.debt);
        uint256 wad = rad / 1e45;
        uint256 amounts = wad = (wad * 1e27) < rad ? wad + 1 : wad;

        _repay(v, gv, amounts, rate);

        // 발행된 부채 흡수
        if (!safeBurn(Stablecoin, msg.sender, amounts)) revert();

        // 제거하려는 유동성이 더 크면 실패 하여야 함
        if (v.collateral < removeAmounts) revert RemoveOverAmount();

        // 대출이 있는 경우
        if (v.debt != 0) {
            // 담보 정보 가져오기
            Collateral memory ci = CollateralInfos[bytes32(0)];

            // 담보의 10분 평균 가격 정보 가져오기
            uint256 collateralValue = _getAveragePrice(bytes32(0));

            // 나의 총 담보에서, 출금하려는
            uint256 valuation = Math.mulDiv(v.collateral - removeAmounts, collateralValue, 1e18);

            //TODO: v.debt 이자율 적용
            uint256 ratio = (valuation * 1e45) / v.debt;

            // 대출 비율 확인, 더스트 범퍼 필요.
            if (ratio <= ci.ratioLimit) revert ReachForTheSky();
        }

        v.collateral -= removeAmounts;
        gv.collateral -= removeAmounts;

        Vaults[msg.sender][bytes32(0)] = v;
        VaultsStatus[bytes32(0)] = gv;

        if (!transferETH(msg.sender, removeAmounts)) revert();
    }

    /**
     * @notice 모든 대출을 상환하면서, 원하는 수량만큼 토큰 유동성을 제거하는 함수 (어차피 빼는건 MAX빼도 됨)
     */
    function repayAndRemove(bytes32 collateralId, uint256 removeAmounts) external {
        // 사용자 금고 가져오기
        Vault memory v = Vaults[msg.sender][collateralId];
        // 전체 금고 가져오기
        Vault memory gv = VaultsStatus[collateralId];
        // 현재 이자율을 업데이트 하면서, 현재 이자율 가져오기
        uint256 rate = _updateAccumulateFee(collateralId);
        uint256 rad = (((v.actualDebt * 1e18) * rate) - v.debt);
        uint256 wad = rad / 1e45;
        uint256 amounts = wad = (wad * 1e27) < rad ? wad + 1 : wad;

        _repay(v, gv, amounts, rate);

        // 토큰 흡수
        if (!safeBurn(Stablecoin, msg.sender, amounts)) revert();

        // 대출이 있는 경우
        if (v.debt != 0) {
            // 담보 정보 가져오기
            Collateral memory ci = CollateralInfos[collateralId];

            // 담보의 10분 평균 가격 정보 가져오기
            uint256 collateralValue = _getAveragePrice(collateralId);

            // 나의 총 담보에서, 출금하려는
            uint256 valuation = Math.mulDiv(v.collateral - removeAmounts, collateralValue, 1e18);

            //TODO: v.debt 이자율 적용
            uint256 ratio = (valuation * 1e45) / v.debt;

            // 대출 비율 확인, 더스트 범퍼 필요.
            if (ratio <= ci.ratioLimit) revert ReachForTheSky();
        }

        v.collateral -= removeAmounts;
        gv.collateral -= removeAmounts;

        Vaults[msg.sender][collateralId] = v;
        VaultsStatus[collateralId] = gv;

        if (!safeTransfer(Stablecoin, msg.sender, removeAmounts)) revert();
    }

    /**
     * @notice 쌓인 수수료 생성 TODO: GovOnly
     */
    function feeCollect(bytes32 collateralId) external {
        Vault memory gv = VaultsStatus[collateralId];
        uint256 rate = AccumulateRate[collateralId];
        uint256 rad = (((gv.actualDebt * 1e18) * rate) - gv.debt);
        uint256 wad = rad / 1e45;
        uint256 amounts = wad = (wad * 1e27) < rad ? wad + 1 : wad;

        gv.actualDebt -= gv.actualDebt;
        gv.debt -= gv.debt;
        VaultsStatus[collateralId] = gv;

        if (!safeMint(Stablecoin, msg.sender, amounts)) revert();
    }

    /**
     * @notice 대출 비율이 맞지 않으면, 청산 시킴, settlement가 선언되기 까지 해당 주소와 해당 자산으로는 부채를 증가시킬 수 없음
     */
    function liquidate(bytes32 collateralId, address target) external {
        // 비율 검사
        // 개인 대출 현황 가져오기
        Vault memory v = Vaults[target][collateralId];
        // 전체 대출 현황
        Vault memory gv = VaultsStatus[collateralId];

        // 담보 정보 가져오기
        Collateral memory c = CollateralInfos[collateralId];

        // 담보되지 않는 스테이블코인 수량
        Vault memory UnbackedDebt = DebtStatus[collateralId];

        uint256 rate = _updateAccumulateFee(collateralId);

        // 담보의 10분 평균 가격 정보 가져오기
        uint256 collateralValue = _getAveragePrice(collateralId);

        // 현재 나의 담보와 가격 정보 곱하기
        uint256 valuation = Math.mulDiv(v.collateral, collateralValue, 1e18);

        // (총 유동성 / 내 대출(1))
        uint256 ratio = (valuation * 1e45) / v.debt;

        // 대출 비율 확인, 범퍼 필요.
        if (ratio <= c.ratioLimit && v.state == VaultState.Normal) {
            // 사용자가 상환해야하는 실질적인 수량 계산
            uint256 rad = (((v.actualDebt * 1e18) * rate) - v.debt);
            uint256 wad = rad / 1e45;
            uint256 amounts = wad = (wad * 1e27) < rad ? wad + 1 : wad;
            uint256 removeActualDebt = (amounts * 1e27) / rate;
            uint256 removeDebt = amounts * rate;

            if (v.actualDebt < removeActualDebt) revert();
            removeDebt = removeDebt <= v.debt ? removeDebt : v.debt;

            v.actualDebt -= removeActualDebt;
            gv.actualDebt -= removeActualDebt;
            v.debt -= removeDebt;
            gv.debt -= removeDebt;

            UnbackedDebt.actualDebt += removeActualDebt;
            UnbackedDebt.debt += removeDebt;
            UnbackedDebt.collateral += v.collateral;

            // 사용자의 대출 및 담보 0로 만들며, 상태를 청산 상태로 만듦.
            v.debt = 0;
            v.actualDebt = 0;
            v.collateral = 0;
            v.state = VaultState.Liquidate;

            // TWAMM Liquidate
        }

        Vaults[target][collateralId] = v;
        VaultsStatus[collateralId] = gv;
        DebtStatus[collateralId] = UnbackedDebt;
    }

    /**
     * @notice Liquidate가 성공적으로 끝난 경우 해당 함수를 호출하여, 판매된 금액으로 unbacked 자산을 줄이며, 해당 vault를 다시 사용할 수 있게 함
     */
    function settlement(bytes32 collateralId, address target) external {}

    /**
     * @notice  연간 수수료를 변경하면서, 전체 대출 현황을 이전 수수료 체계에 적용시키고 새로운 이자율로 변경
     * @dev     GovOnly
     * @param   newRate 새로운 초당 이자율
     */
    function updateRate(bytes32 collateralId, uint256 newRate) external {
        // 전체 대출 정보 가져오기
        Vault memory gv = VaultsStatus[collateralId];

        // 담보의 누적 이자율 가져오기
        uint256 rate = AccumulateRate[collateralId];

        // 만들어진 누적 레이트와 현재 레이트의 차이 계산
        int256 diff = _calculateNewRate(collateralId, newRate, rate);

        int256 rad = int256(gv.actualDebt) * diff;

        // 수수료 누적
        gv.actualDebt += uint256(rad) / 1e27;

        // 전체
        gv.debt += uint256(rad);

        VaultsStatus[collateralId] = gv;

        // 차이만큼 누적 레이트에 변경
        AccumulateRate[collateralId] += uint256(diff);
    }

    //---------------------------------------------------//
    // Public Function area
    //---------------------------------------------------//

    //---------------------------------------------------//
    // Internal Function area
    //---------------------------------------------------//

    /**
     * @notice 부채를 증가 시키는데 사용되는 값들을 업데이트 하는 내부 함수
     */
    function _draw(Vault memory v, Vault memory gv, uint256 amounts, uint256 rate) internal pure {
        unchecked {
            // 내부에서 계산하기 편하게 1e18 곱함
            // 곱한 금액으로 내부 부채 업데이트
            v.actualDebt += amounts;
            gv.actualDebt += amounts;

            // 이자율이 적용된 부채로 업데이트
            v.debt += (amounts * rate);
            gv.debt += (amounts * rate);
        }
    }

    /**
     * @notice 부채를 줄이는데 사용되는 값들을 업데이트 하는 내부 함수
     */
    function _repay(Vault memory v, Vault memory gv, uint256 amounts, uint256 rate) internal pure {
        uint256 removeActualDebt = (amounts * 1e27) / rate;
        uint256 removeDebt = amounts * rate;

        if (v.actualDebt < removeActualDebt) revert();
        removeDebt = removeDebt <= v.debt ? removeDebt : v.debt;

        v.actualDebt -= removeActualDebt;
        gv.actualDebt -= removeActualDebt;

        v.debt -= removeDebt;
        gv.debt -= removeDebt;
    }

    /**
     * @notice 시간에 따라, 기존 이자율에 따라 이자 누적하는 함수
     */
    function _updateAccumulateFee(bytes32 collateralId) internal returns (uint256 rate) {
        rate = AccumulateRate[collateralId];

        // 해당 담보 유형이 초기화 되지 않았다면,
        if (rate == 0) revert NotInitialzedCollateral();

        Vault memory gv = VaultsStatus[collateralId];

        // 누적 이자율과 현재 이자율의 차이 계산
        int256 diff = _calculateOldRate(collateralId, rate);

        int256 rad = int256(gv.actualDebt) * diff;

        // 수수료 누적
        gv.actualDebt += uint256(rad) / 1e27;

        // 전체
        gv.debt += uint256(rad);

        // 담보 정보 업데이트
        VaultsStatus[collateralId] = gv;

        // 차이만큼 누적 이자율에 누적
        AccumulateRate[collateralId] += uint256(diff);
    }

    /**
     * @notice 기존 이자율에 따라, 시간동안의 이자율 차이를 반환
     */
    function _calculateOldRate(bytes32 collateralId, uint256 currentAccumulateRate) internal returns (int256 diff) {
        // 담보에 대한 정보 가져오기
        Collateral memory gc = CollateralInfos[collateralId];
        // 담보 정보에 기록된 이자율을 기반하여, 새로운 누적 이자율 계산
        uint256 rate =
            rmul(rpow(Base + gc.currentRate, block.timestamp - gc.latestTimestamp, 1e27), currentAccumulateRate);
        // 새로운 이자율과 이전 누적 이자율 차이 계산
        diff = int256(rate) - int256(currentAccumulateRate);
        // 마지막 업데이트 시간 업데이트
        gc.latestTimestamp = block.timestamp;
        // 최종 담보 정보 접근 시간 변경
        CollateralInfos[collateralId] = gc;
    }

    /**
     * @notice 기존 이자율과, 새로운 이자율 간 차이를 반환.
     */
    function _calculateNewRate(bytes32 collateralId, uint256 newRate, uint256 currentAccumulateRate)
        internal
        returns (int256 diff)
    {
        // 담보에 대한 정보 가져오기
        Collateral memory gc = CollateralInfos[collateralId];
        uint256 rate = rmul(rpow(Base + newRate, block.timestamp - gc.latestTimestamp, 1e27), currentAccumulateRate);
        diff = int256(rate) - int256(currentAccumulateRate);
        (gc.currentRate, gc.latestTimestamp) = (newRate, block.timestamp);
        CollateralInfos[collateralId] = gc;
    }

    /**
     * @notice  Price Feed로 부터 10분 평균 담보가격을 가져옵니다.
     * @param   collateralId    담보의 고유 아이디
     */
    function _getAveragePrice(bytes32 collateralId) internal view returns (uint256 collateralValue) {
        Collateral memory c = CollateralInfos[collateralId];
        (int24 arithmeticMeanTick,) = c.priceFeed.consultWithSeconds(600);
        uint160 sqrtPrice = TickMath.getSqrtRatioAtTick(arithmeticMeanTick);
        collateralValue = Math.mulDiv(uint256(sqrtPrice) * uint256(sqrtPrice), 1e18, 1 << 192);
    }

    /**
     * @notice  ETH를 Low-Level로 전송하는 함수
     * @param   to      ETH를 받을 주소
     * @param   amount  ETH를 보낼 수량
     */
    function transferETH(address to, uint256 amount) internal returns (bool success) {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            success := call(gas(), to, amount, 0, 0, 0, 0)
        }
    }

    function safeMint(IERC20 token, address to, uint256 amount) internal returns (bool success) {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            let freePointer := mload(0x40)
            mstore(freePointer, 0x40c10f1900000000000000000000000000000000000000000000000000000000)
            mstore(add(freePointer, 4), and(to, 0xffffffffffffffffffffffffffffffffffffffff))
            mstore(add(freePointer, 36), amount)

            let callStatus := call(gas(), token, 0, freePointer, 68, 0, 0)

            let returnDataSize := returndatasize()
            if iszero(callStatus) {
                // Copy the revert message into memory.
                returndatacopy(0, 0, returnDataSize)

                // Revert with the same message.
                revert(0, returnDataSize)
            }
            switch returnDataSize
            case 32 {
                // Copy the return data into memory.
                returndatacopy(0, 0, returnDataSize)

                // Set success to whether it returned true.
                success := iszero(iszero(mload(0)))
            }
            case 0 {
                // There was no return data.
                success := 1
            }
            default {
                // It returned some malformed input.
                success := 0
            }
        }
    }

    function safeBurn(IERC20 token, address from, uint256 amount) internal returns (bool success) {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            let freePointer := mload(0x40)
            mstore(freePointer, 0x9dc29fac00000000000000000000000000000000000000000000000000000000)
            mstore(add(freePointer, 4), and(from, 0xffffffffffffffffffffffffffffffffffffffff))
            mstore(add(freePointer, 36), amount)

            let callStatus := call(gas(), token, 0, freePointer, 68, 0, 0)

            let returnDataSize := returndatasize()
            if iszero(callStatus) {
                // Copy the revert message into memory.
                returndatacopy(0, 0, returnDataSize)

                // Revert with the same message.
                revert(0, returnDataSize)
            }
            switch returnDataSize
            case 32 {
                // Copy the return data into memory.
                returndatacopy(0, 0, returnDataSize)

                // Set success to whether it returned true.
                success := iszero(iszero(mload(0)))
            }
            case 0 {
                // There was no return data.
                success := 1
            }
            default {
                // It returned some malformed input.
                success := 0
            }
        }
    }

    /**
     * @notice  ERC20 형태의 토큰을 Low-Level로 `transferFrom` 호출
     * @param   token   ERC20 토큰 컨트랙트 주소
     * @param   from    토큰을 보낼 주소
     * @param   to      토큰을 받을 주소
     * @param   amount  받을 토큰의 수량
     */
    function safeTransferFrom(IERC20 token, address from, address to, uint256 amount) internal returns (bool success) {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            let freePointer := mload(0x40)
            mstore(freePointer, 0x23b872dd00000000000000000000000000000000000000000000000000000000)
            mstore(add(freePointer, 4), and(from, 0xffffffffffffffffffffffffffffffffffffffff))
            mstore(add(freePointer, 36), and(to, 0xffffffffffffffffffffffffffffffffffffffff))
            mstore(add(freePointer, 68), amount)

            let callStatus := call(gas(), token, 0, freePointer, 100, 0, 0)

            let returnDataSize := returndatasize()
            if iszero(callStatus) {
                // Copy the revert message into memory.
                returndatacopy(0, 0, returnDataSize)

                // Revert with the same message.
                revert(0, returnDataSize)
            }
            switch returnDataSize
            case 32 {
                // Copy the return data into memory.
                returndatacopy(0, 0, returnDataSize)

                // Set success to whether it returned true.
                success := iszero(iszero(mload(0)))
            }
            case 0 {
                // There was no return data.
                success := 1
            }
            default {
                // It returned some malformed input.
                success := 0
            }
        }
    }

    /**
     * @notice  ERC20 형태의 토큰을 Low-Level로 `transfer` 호출
     * @param   token   ERC20 토큰 컨트랙트 주소
     * @param   to      토큰을 받을 주소
     * @param   amount  받을 토큰의 수량
     */
    function safeTransfer(IERC20 token, address to, uint256 amount) internal returns (bool success) {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            let freePointer := mload(0x40)
            mstore(freePointer, 0xa9059cbb00000000000000000000000000000000000000000000000000000000)
            mstore(add(freePointer, 4), and(to, 0xffffffffffffffffffffffffffffffffffffffff))
            mstore(add(freePointer, 36), amount)

            let callStatus := call(gas(), token, 0, freePointer, 68, 0, 0)

            let returnDataSize := returndatasize()
            if iszero(callStatus) {
                // Copy the revert message into memory.
                returndatacopy(0, 0, returnDataSize)

                // Revert with the same message.
                revert(0, returnDataSize)
            }
            switch returnDataSize
            case 32 {
                // Copy the return data into memory.
                returndatacopy(0, 0, returnDataSize)

                // Set success to whether it returned true.
                success := iszero(iszero(mload(0)))
            }
            case 0 {
                // There was no return data.
                success := 1
            }
            default {
                // It returned some malformed input.
                success := 0
            }
        }
    }

    //---------------------------------------------------//
    // Private Function area
    //---------------------------------------------------//
    function add(uint256 x, uint256 y) private pure returns (uint256 z) {
        unchecked {
            if ((z = x + y) < x) revert();
        }
        // require((z = x + y) >= x, "ds-math-add-overflow");
    }

    function mul(uint256 x, uint256 y) private pure returns (uint256 z) {
        require(y == 0 || (z = x * y) / y == x, "ds-math-mul-overflow");
    }

    //rounds to zero if x*y < WAD / 2
    function rmul(uint256 x, uint256 y) private pure returns (uint256 z) {
        z = (mul(x, y) + (1e27 / 2)) / 1e27;
    }

    function rpow(uint256 x, uint256 n, uint256 b) private pure returns (uint256 z) {
        assembly {
            switch x
            case 0 {
                switch n
                case 0 { z := b }
                default { z := 0 }
            }
            default {
                switch mod(n, 2)
                case 0 { z := b }
                default { z := x }
                let half := div(b, 2) // for rounding.
                for { n := div(n, 2) } n { n := div(n, 2) } {
                    let xx := mul(x, x)
                    if iszero(eq(div(xx, x), x)) { revert(0, 0) }
                    let xxRound := add(xx, half)
                    if lt(xxRound, xx) { revert(0, 0) }
                    x := div(xxRound, b)
                    if mod(n, 2) {
                        let zx := mul(z, x)
                        if and(iszero(iszero(x)), iszero(eq(div(zx, x), z))) { revert(0, 0) }
                        let zxRound := add(zx, half)
                        if lt(zxRound, zx) { revert(0, 0) }
                        z := div(zxRound, b)
                    }
                }
            }
        }
    }

    function minValue(uint256 a, uint256 b) private pure returns (uint256 result) {
        assembly {
            // a * (a < b) 계산하고 메모리 위치 0x40에 저장
            mstore(0x80, mul(a, lt(a, b)))

            // b * (a => b) 계산하고 메모리 위치 0x60에 저장
            mstore(0xa0, mul(b, or(gt(a, b), eq(a, b))))

            // 두 결과를 더하여 반환
            result := add(mload(0x80), mload(0xa0))
        }
    }

    function maxValue(uint256 a, uint256 b) private pure returns (uint256 result) {
        assembly {
            // a * (a > b) 계산하고 메모리 위치 0x40에 저장
            mstore(0x80, mul(a, gt(a, b)))

            // b * (a <= b) 계산하고 메모리 위치 0x60에 저장
            mstore(0xa0, mul(b, or(lt(a, b), eq(a, b))))

            // 두 결과를 더하여 반환
            result := add(mload(0x80), mload(0xa0))
        }
    }
}
