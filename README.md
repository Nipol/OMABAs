# OMABAs, (Over-collateralized Mint/Burn Asset System)

해당 저장소는 과담보 대출을 수행하는 솔리디티 코드의 집합입니다. 기본 시스템을 매번 만드는게 시간이 오래걸려서, 잘 작동하는 코드들만 모아 하나로 묶었습니다. 전체적인 설계 기조는 MakerDAO의 MCD 코드를 참고하였으며, 컨트랙트 사이의 호출을 줄이고 사적으로 적용하는 최적화 방안들이 적용되었습니다. 

해당 저장소는 다음의 기능을 포함합니다.

 * Yul로 작성된 ERC20
 * Native를 이용한 ERC20의 생성과 소각
 * ERC20를 이용한 ERC20의 생성과 소각
 * Price Feed 읽기
 * 작성하다 귀찮아진 테스트 코드 (그렇지만 작동을 확인할 만큼은 충분합니다)

## Price Feed

해당 시스템에서 자산을 추적하는 이름은 전부 Price Feed로 명명되어 있습니다. `Oracle 이라는 이름은 사치입니다.` 자산의 가격은 Uniswap V3부터 제공되었던 `Tick`` 이라는 기준을 사용합니다. 해당 테스트코드에서는 Mocking과 On-chain Price Feed를 읽을 수 있도록 구성되어 있기도 합니다.

이러한 Price Feed를 구성하시려면, [FeedForFeed](https://github.com/Nipol/FeedForFeed)를 참고하세요.

## 청산

대체로 청산 시스템은, 이러한 시스템의 완성이며 생성되는 자산의 안정성을 결정하는 중요한 기능입니다. 따라서 해당 저장소에서는 이러한 청산 시스템이 단 하나도 포함되어 있지 않다는 것을 말씀드립니다.