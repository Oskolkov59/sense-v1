// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.11;

import { TestHelper, MockTargetLike } from "../test-helpers/TestHelper.sol";
import { MockAdapter, MockCropAdapter } from "../test-helpers/mocks/MockAdapter.sol";
import { MockFactory, MockCropFactory } from "../test-helpers/mocks/MockFactory.sol";
import { MockToken } from "../test-helpers/mocks/MockToken.sol";
import { MockTarget } from "../test-helpers/mocks/MockTarget.sol";
import { DateTimeFull } from "../test-helpers/DateTimeFull.sol";
import { BaseAdapter } from "../../adapters/abstract/BaseAdapter.sol";
import { BaseFactory } from "../../adapters/abstract/factories/BaseFactory.sol";
import { FixedMath } from "../../external/FixedMath.sol";
import { Errors } from "@sense-finance/v1-utils/src/libs/Errors.sol";
import { Constants } from "../test-helpers/Constants.sol";

contract MockRevertAdapter is MockAdapter {
    constructor(BaseAdapter.AdapterParams memory _adapterParams)
        MockAdapter(address(0), address(0), address(0), 1, _adapterParams)
    {}

    function getUnderlyingPrice() external view virtual override returns (uint256) {
        revert("ERROR");
    }
}

contract MockRevertFactory is MockFactory {
    constructor(BaseFactory.FactoryParams memory _factoryParams) MockFactory(address(0), _factoryParams) {}

    function deployAdapter(address _target, bytes memory data) external override returns (address adapter) {
        BaseAdapter.AdapterParams memory adapterParams;
        adapter = address(new MockRevertAdapter(adapterParams));
        _setGuard(adapter);
    }
}

contract Factories is TestHelper {
    using FixedMath for uint256;

    function testDeployFactory() public {
        BaseFactory.FactoryParams memory factoryParams = BaseFactory.FactoryParams({
            stake: address(stake),
            oracle: ORACLE,
            ifee: ISSUANCE_FEE,
            stakeSize: STAKE_SIZE,
            minm: MIN_MATURITY,
            maxm: MAX_MATURITY,
            mode: MODE,
            tilt: 0,
            guard: 123e18
        });
        MockCropFactory someFactory = new MockCropFactory(address(divider), factoryParams, address(reward));

        assertTrue(address(someFactory) != address(0));
        assertEq(someFactory.divider(), address(divider));
        (
            address oracle,
            address stake,
            uint256 stakeSize,
            uint256 minm,
            uint256 maxm,
            uint256 ifee,
            uint16 mode,
            uint64 tilt,
            uint256 guard
        ) = someFactory.factoryParams();

        assertEq(oracle, ORACLE);
        assertEq(stake, address(stake));
        assertEq(ifee, ISSUANCE_FEE);
        assertEq(stakeSize, STAKE_SIZE);
        assertEq(minm, MIN_MATURITY);
        assertEq(maxm, MAX_MATURITY);
        assertEq(mode, MODE);
        assertEq(tilt, 0);
        assertEq(guard, 123e18);
        assertEq(someFactory.reward(), address(reward));
    }

    function testDeployAdapter() public {
        MockToken someReward = new MockToken("Some Reward", "SR", 18);
        MockTargetLike someTarget = MockTargetLike(deployMockTarget(address(underlying), "Some Target", "ST", 18));

        address[] memory rewardTokens = new address[](1);
        rewardTokens[0] = address(someReward);
        MockCropFactory someFactory = MockCropFactory(deployCropsFactory(address(someTarget), rewardTokens, false));

        divider.setPeriphery(alice);
        MockCropAdapter adapter = MockCropAdapter(someFactory.deployAdapter(address(someTarget), ""));
        assertTrue(address(adapter) != address(0));

        (address oracle, address stake, uint256 stakeSize, uint256 minm, uint256 maxm, , , ) = adapter.adapterParams();
        assertEq(adapter.divider(), address(divider));
        assertEq(adapter.target(), address(someTarget));
        assertEq(adapter.name(), "Some Target Adapter");
        assertEq(adapter.symbol(), "ST-adapter");
        assertEq(adapter.ifee(), ISSUANCE_FEE);
        assertEq(oracle, ORACLE);
        assertEq(stake, address(stake));
        assertEq(stakeSize, STAKE_SIZE);
        assertEq(minm, MIN_MATURITY);
        assertEq(maxm, MAX_MATURITY);
        assertEq(adapter.mode(), MODE);
        assertEq(adapter.reward(), address(someReward));
        uint256 scale = adapter.scale();
        assertEq(scale, 1e18);

        // Guard has been calculated with underlying-ETH (18 decimals),
        // target-underlying (18 decimals) and ETH-USD (8 decimals)
        (, , uint256 guard, ) = divider.adapterMeta(address(adapter));
        uint256 tDecimals = MockToken(adapter.target()).decimals();

        // On this test we assert that the guard calculated is close to the one calculated below
        // underlying-ETH price (18 decimals)
        uint256 underlyingPriceInEth = adapter.getUnderlyingPrice();

        // Calculate Underlying-USD price (normalised to 18 deicmals)
        uint256 price = underlyingPriceInEth.fmul(Constants.DEFAULT_CHAINLINK_ETH_PRICE, 1e8);

        // target-USD price (18 decimals)
        price = scale.fmul(price, 10**tDecimals);

        // Convert DEFAULT_GUARD (which is $100'000 in 18 decimals) to target
        // using target's price (18 decimals)
        uint256 guardInTarget = DEFAULT_GUARD.fdiv(price, 10**tDecimals);
        assertClose(guard, guardInTarget, guard.fmul(0.001e18));
    }

    function testDeployAdapterDoesNotSetGuardWhenNotGuarded() public {
        // Set guarded mode in false
        divider.setGuarded(false);

        MockTargetLike someTarget = MockTargetLike(deployMockTarget(address(underlying), "Some Target", "ST", 18));
        MockFactory someFactory = MockFactory(deployFactory(address(someTarget)));
        divider.setPeriphery(alice);
        address adapter = someFactory.deployAdapter(address(someTarget), "");
        assertTrue(adapter != address(0));

        (address oracle, address stake, uint256 stakeSize, uint256 minm, uint256 maxm, , , ) = MockAdapter(adapter)
            .adapterParams();
        assertEq(MockAdapter(adapter).divider(), address(divider));
        assertEq(MockAdapter(adapter).target(), address(someTarget));
        assertEq(MockAdapter(adapter).name(), "Some Target Adapter");
        assertEq(MockAdapter(adapter).symbol(), "ST-adapter");
        assertEq(MockAdapter(adapter).ifee(), ISSUANCE_FEE);
        assertEq(oracle, ORACLE);
        assertEq(stake, address(stake));
        assertEq(stakeSize, STAKE_SIZE);
        assertEq(minm, MIN_MATURITY);
        assertEq(maxm, MAX_MATURITY);
        assertEq(MockAdapter(adapter).mode(), MODE);

        uint256 scale = MockAdapter(adapter).scale();
        assertEq(scale, 1e18);

        (, , uint256 guard, ) = divider.adapterMeta(address(adapter));
        assertEq(guard, 0);
    }

    function testDeployAdapterAndinitializeSeries() public {
        MockToken someReward = new MockToken("Some Reward", "SR", 18);
        MockToken someUnderlying = new MockToken("Some Underlying", "SU", 18);
        MockTargetLike someTarget = MockTargetLike(deployMockTarget(address(underlying), "Some Target", "ST", 18));

        address[] memory rewardTokens = new address[](1);
        rewardTokens[0] = address(someReward);
        MockCropFactory someFactory = MockCropFactory(deployCropsFactory(address(someTarget), rewardTokens, false));

        address f = periphery.deployAdapter(address(someFactory), address(someTarget), "");
        assertTrue(f != address(0));
        uint256 scale = MockAdapter(f).scale();
        assertEq(scale, 1e18);
        hevm.warp(block.timestamp + 1 days);
        uint256 maturity = DateTimeFull.timestampFromDateTime(2021, 10, 1, 0, 0, 0);
        (address principal, address yield) = periphery.sponsorSeries(f, maturity, true);
        assertTrue(principal != address(0));
        assertTrue(yield != address(0));
    }

    function testCantDeployAdapterIfNotPeriphery() public {
        MockToken someUnderlying = new MockToken("Some Underlying", "SU", 18);
        MockTarget someTarget = new MockTarget(address(someUnderlying), "Some Target", "ST", 18);
        factory.supportTarget(address(someTarget), true);
        hevm.expectRevert(abi.encodeWithSelector(Errors.OnlyPeriphery.selector));
        factory.deployAdapter(address(someTarget), "");
    }

    function testFailDeployAdapterIfAlreadyExists() public {
        divider.setPeriphery(alice);
        factory.deployAdapter(address(target), "");
    }
}
