// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "../interfaces/IBRDToken.sol";

contract BRDToken is ERC20("BRDToken", "BRD"), IBRDToken, Ownable {
    /* ========== EXTERNAL MUTATIVE FUNCTIONS ========== */

    /**
     * @dev allow owner to mint
     * @param _to mint token to address
     * @param _amount amount of BRD to mint
     */
    function mint(address _to, uint256 _amount) external override onlyOwner {
        _mint(_to, _amount);
    }
}
