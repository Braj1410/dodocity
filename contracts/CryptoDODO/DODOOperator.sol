// SPDX-License-Identifier: MIT

pragma solidity =0.6.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/introspection/IERC165.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "../interfaces/IGeneScience.sol";
import "../interfaces/ICryptoDODOEnergyListener.sol";
import "./DODOBreed.sol";

contract DODOOperator is DODOBreed {
    using Address for address;

    address public operator;

    /*
     * bytes4(keccak256('onCryptoDODOEnergyChanged(uint256,uint256,uint256)')) == 0x5a864e1c
     */
    bytes4
        private constant _INTERFACE_ID_CRYPTO_DODO_ENERGY_LISTENER = 0x5a864e1c;

    /* ========== EVENTS ========== */

    /**
     * @dev Event for when DODO's energy changed from `fromEnergy`
     */
    event EnergyChanged(
        uint256 indexed id,
        uint256 oldEnergy,
        uint256 newEnergy
    );

    /* ========== OPERATOR ONLY FUNCTION ========== */

    function updateDODOEnergy(
        address _owner,
        uint256 _id,
        uint32 _newEnergy
    ) external onlyOperator nonReentrant {
        require(_newEnergy > 0, "CryptoDODO: invalid energy");

        require(
            isOwnerOf(_owner, _id),
            "CryptoDODO: DODO does not belongs to owner"
        );

        DODO storage thisDODO = DODOs[_id];
        uint32 oldEnergy = thisDODO.energy;
        thisDODO.energy = _newEnergy;

        emit EnergyChanged(_id, oldEnergy, _newEnergy);
        _doSafeEnergyChangedAcceptanceCheck(_owner, _id, oldEnergy, _newEnergy);
    }

    /**
     * @dev Transfers operator role to different address
     * Can only be called by the current operator.
     */
    function transferOperator(address _newOperator) external onlyOperator {
        require(
            _newOperator != address(0),
            "CryptoDODO: new operator is the zero address"
        );
        operator = _newOperator;
    }

    /* ========== MODIFIERS ========== */

    /**
     * @dev Throws if called by any account other than operator.
     */
    modifier onlyOperator() {
        require(
            operator == _msgSender(),
            "CryptoDODO: caller is not the operator"
        );
        _;
    }

    /* =========== PRIVATE ========= */

    function _doSafeEnergyChangedAcceptanceCheck(
        address _to,
        uint256 _id,
        uint256 _oldEnergy,
        uint256 _newEnergy
    ) private {
        if (_to.isContract()) {
            if (
                IERC165(_to).supportsInterface(
                    _INTERFACE_ID_CRYPTO_DODO_ENERGY_LISTENER
                )
            ) {
                ICryptoDODOEnergyListener(_to).onCryptoDODOEnergyChanged(
                    _id,
                    _oldEnergy,
                    _newEnergy
                );
            }
        }
    }
}
