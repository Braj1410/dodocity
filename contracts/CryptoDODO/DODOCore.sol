// SPDX-License-Identifier: MIT

pragma solidity =0.6.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/IGeneScience.sol";
import "./DODOOperator.sol";

contract DODOCore is DODOOperator {
    /**
     * @dev Initializes crypto DODO contract.
     * @param _alpa ALPA ERC20 contract address
     * @param _devAddress dev address.
     * @param _stakingAddress staking address.
     */
    constructor(
        IERC20 _alpa,
        IGeneScience _geneScience,
        address _operator,
        address _devAddress,
        address _stakingAddress
    ) public {
        alpa = _alpa;
        geneScience = _geneScience;
        operator = _operator;
        devAddress = _devAddress;
        stakingAddress = _stakingAddress;

        // start with the mythical genesis DODO
        _createGen0DODO(uint256(-1), 0, msg.sender);
    }

    /* ========== OWNER MUTATIVE FUNCTION ========== */

    /**
     * @dev Allows owner to withdrawal the balance available to the contract.
     */
    function withdrawBalance(uint256 _amount, address payable _to)
        external
        onlyOwner
    {
        _to.transfer(_amount);
    }

    /**
     * @dev pause crypto DODO contract stops any further hatching.
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @dev unpause crypto DODO contract.
     */
    function unpause() external onlyOwner {
        _unpause();
    }
}
