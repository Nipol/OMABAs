// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity ^0.8.13;

import "../src/IFFF.sol";

contract FFFM is IFFF {
    int24 Tick;
    int56 _averageTickCumulative;
    uint160 _secondsPerVolumeCumulativeX128;
    uint16 _frameIndex;
    uint16 _frameCardinality;
    uint16 _frameCardinalityNext;

    constructor(int24 tick) {
        Tick = tick;
    }

    function frames(uint256)
        external
        returns (uint32 blockTimestamp, int56 averageTickCumulative, uint160 secondsPerVolumeCumulativeX128)
    {
        blockTimestamp = uint32(block.timestamp);
        averageTickCumulative = _averageTickCumulative += 1;
        secondsPerVolumeCumulativeX128 = _secondsPerVolumeCumulativeX128 += 1;
    }

    function slot0()
        external
        returns (uint16 frameIndex, uint16 frameCardinality, uint16 frameCardinalityNext, uint32 latestTimestamp)
    {
        frameIndex = _frameIndex += 1;
        frameCardinality = frameCardinality += 1;
        frameCardinalityNext = frameCardinalityNext += 1;
        latestTimestamp = uint32(block.timestamp);
    }

    function commit(int24, uint128) external {}

    function consultWithSeconds(uint32)
        external
        view
        returns (int24 arithmeticMeanTick, uint128 harmonicMeanLiquidity)
    {
        arithmeticMeanTick = Tick;
        harmonicMeanLiquidity = 0;
    }

    function consultWithSeconds(uint32, uint32)
        external
        view
        returns (int24 arithmeticMeanTick, uint128 harmonicMeanLiquidity)
    {
        arithmeticMeanTick = Tick;
        harmonicMeanLiquidity = 0;
    }
}
