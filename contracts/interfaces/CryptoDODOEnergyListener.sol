// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin/contracts/introspection/ERC165.sol";
import "./ICryptoDODOEnergyListener.sol";

abstract contract CryptoDODOEnergyListener is
    ERC165,
    ICryptoDODOEnergyListener
{
    constructor() public {
        _registerInterface(
            CryptoDODOEnergyListener(0).onCryptoDODOEnergyChanged.selector
        );
    }
}
