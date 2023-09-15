// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity ^0.8.13;

interface IFFF {
    function frames(uint256 index)
        external
        returns (uint32 blockTimestamp, int56 averageTickCumulative, uint160 secondsPerVolumeCumulativeX128);
    function slot0()
        external
        returns (uint16 frameIndex, uint16 frameCardinality, uint16 frameCardinalityNext, uint32 latestTimestamp);
    function commit(int24 averageTick, uint128 volume) external;
    function consultWithSeconds(uint32 secondsAgo)
        external
        view
        returns (int24 arithmeticMeanTick, uint128 harmonicMeanLiquidity);
    function consultWithSeconds(uint32 secondsAgo, uint32 start)
        external
        view
        returns (int24 arithmeticMeanTick, uint128 harmonicMeanLiquidity);
}
