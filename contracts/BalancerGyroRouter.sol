//SPDX-License-Identifier: Unlicense
pragma solidity ^0.7.0;

import "./GyroRouter.sol";
import "./balancer/BPool.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract BalancerGyroRouter is GyroRouter {
    mapping(address => address[]) public pools;

    function deposit(address[] memory _tokensIn, uint256[] memory _amountsIn)
        external
        override
    {
        for (uint256 i = 0; i < _tokensIn.length; i++) {
            address token = _tokensIn[i];
            uint256 amount = _amountsIn[i];
            bool success =
                IERC20(token).transferFrom(msg.sender, address(this), amount);
            require(
                success,
                "failed to transfer tokens from GyroFund to GryoRouter"
            );

            BPool pool = BPool(choosePoolToDeposit(token, amount));
            uint256 poolAmountOut =
                calcPoolOutGivenSingleIn(pool, token, amount);
            uint256[] memory amountsIn = createAmounts(pool, token, amount);
            pool.joinPool(poolAmountOut, amountsIn);

            success = pool.transfer(msg.sender, poolAmountOut);
            require(success, "failed to transfer BPT to GyroFund");
        }
    }

    function withdraw(address[] memory _tokensOut, uint256[] memory _amountsOut)
        external
        override
    {
        for (uint256 i = 0; i < _tokensOut.length; i++) {
            address token = _tokensOut[i];
            uint256 amount = _amountsOut[i];
            BPool pool = BPool(choosePoolToWithdraw(token, amount));
            uint256 poolAmountIn =
                calcPoolInGivenSingleOut(pool, token, amount);

            bool success =
                pool.transferFrom(msg.sender, address(this), poolAmountIn);
            require(
                success,
                "failed to transfer BPT from GyroFund to GryoRouter"
            );

            uint256[] memory amountsOut = createAmounts(pool, token, amount);
            pool.exitPool(poolAmountIn, amountsOut);

            success = IERC20(token).transfer(msg.sender, amount);
            require(success, "failed to transfer token to GyroFund");
        }
    }

    function createAmounts(
        BPool pool,
        address token,
        uint256 amount
    ) internal view returns (uint256[] memory) {
        address[] memory poolTokens = pool.getCurrentTokens();
        uint256[] memory amounts = new uint256[](poolTokens.length);
        bool found = false;
        for (uint256 i = 0; i < poolTokens.length; i++) {
            if (poolTokens[i] == token) {
                amounts[i] = amount;
                found = true;
                break;
            }
        }
        require(found, "token not found in pool");
        return amounts;
    }

    function calcPoolOutGivenSingleIn(
        BPool pool,
        address _token,
        uint256 _amount
    ) internal view returns (uint256) {
        uint256 tokenBalanceIn = pool.getBalance(_token);
        uint256 tokenWeightIn = pool.getDenormalizedWeight(_token);
        uint256 poolSupply = pool.totalSupply();
        uint256 totalWeight = pool.getTotalDenormalizedWeight();
        uint256 swapFee = pool.getSwapFee();
        return
            pool.calcPoolOutGivenSingleIn(
                tokenBalanceIn,
                tokenWeightIn,
                poolSupply,
                totalWeight,
                _amount,
                swapFee
            );
    }

    function calcPoolInGivenSingleOut(
        BPool pool,
        address _token,
        uint256 _amount
    ) internal view returns (uint256) {
        uint256 tokenBalanceOut = pool.getBalance(_token);
        uint256 tokenWeightOut = pool.getDenormalizedWeight(_token);
        uint256 poolSupply = pool.totalSupply();
        uint256 totalWeight = pool.getTotalDenormalizedWeight();
        uint256 swapFee = pool.getSwapFee();
        return
            pool.calcPoolInGivenSingleOut(
                tokenBalanceOut,
                tokenWeightOut,
                poolSupply,
                totalWeight,
                _amount,
                swapFee
            );
    }

    function choosePoolToDeposit(address _token, uint256 _amount)
        private
        view
        returns (address)
    {
        address[] storage candidates = pools[_token];
        require(candidates.length > 0, "token not supported");
        // TODO: choose better
        return candidates[_amount % candidates.length];
    }

    function choosePoolToWithdraw(address _token, uint256 _amount)
        private
        view
        returns (address)
    {
        address[] storage candidates = pools[_token];
        require(candidates.length > 0, "token not supported");
        // TODO: choose better
        return candidates[_amount % candidates.length];
    }
}
