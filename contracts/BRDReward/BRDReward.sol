// SPDX-License-Identifier: MIT

pragma solidity =0.6.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

// BRDReward
contract BRDReward is ERC20("BRDReward", "xBRD") {
    using SafeMath for uint256;

    /* ========== STATE VARIABLES ========== */

    IERC20 public BRD;

    /* ========== CONSTRUCTOR ========== */

    /**
     * Define the BRD token contract
     */

    constructor(IERC20 _BRD) public {
        BRD = _BRD;
    }

    /* ========== EXTERNAL MUTATIVE FUNCTIONS ========== */

    /**
     * Locks BRD and mints xBRD
     * @param _amount of BRD to stake
     */
    function enter(uint256 _amount) external {
        // Gets the amount of BRD locked in the contract
        uint256 totalBRD = BRD.balanceOf(address(this));

        // Gets the amount of xBRD in existence
        uint256 totalShares = totalSupply();

        // If no xBRD exists, mint it 1:1 to the amount put in
        if (totalShares == 0 || totalBRD == 0) {
            _mint(msg.sender, _amount);
        } else {
            // Calculate and mint the amount of xBRD the BRD is worth. The ratio will change overtime, as xBRD is burned/minted and BRD deposited + gained from fees / withdrawn.
            uint256 what = _amount.mul(totalShares).div(totalBRD);
            _mint(msg.sender, what);
        }

        // Lock the BRD in the contract
        BRD.transferFrom(msg.sender, address(this), _amount);
    }

    /**
     * Claim back your BRDs.
     * Unclocks the staked + gained BRD and burns xBRD
     * @param _share amount of xBRD
     */
    function leave(uint256 _share) external {
        // Gets the amount of xBRD in existence
        uint256 totalShares = totalSupply();

        // Calculates the amount of BRD the xBRD is worth
        uint256 what = _share.mul(BRD.balanceOf(address(this))).div(
            totalShares
        );
        _burn(msg.sender, _share);

        BRD.transfer(msg.sender, what);
    }
}
