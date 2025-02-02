// SPDX-License-Identifier: MIT

pragma solidity =0.6.12;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/EnumerableMap.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

import "./DODOToken.sol";
import "../interfaces/ICryptoDODO.sol";

contract DODOBreed is DODOToken, ICryptoDODO, ReentrancyGuard, Pausable {
    using SafeMath for uint256;
    using EnumerableMap for EnumerableMap.UintToAddressMap;

    /* ========== EVENTS ========== */

    // The Hatched event is fired when two DODO successfully hached an egg.
    event Hatched(
        uint256 indexed eggId,
        uint256 matronId,
        uint256 sireId,
        uint256 cooldownEndBlock
    );

    // The GrantedToBreed event is fired whne an DODO's owner granted
    // addr account to use DODOId as sire to breed.
    event GrantedToBreed(uint256 indexed DODOId, address addr);

    /* ========== VIEWS ========== */

    /**
     * Returns all the relevant information about a specific DODO.
     * @param _id The ID of the DODO of interest.
     */
    function getDODO(uint256 _id)
        external
        override
        view
        returns (
            uint256 id,
            bool isReady,
            uint256 cooldownEndBlock,
            uint256 birthTime,
            uint256 matronId,
            uint256 sireId,
            uint256 hatchingCost,
            uint256 hatchingCostMultiplier,
            uint256 hatchCostMultiplierEndBlock,
            uint256 generation,
            uint256 gene,
            uint256 energy,
            uint256 state
        )
    {
        DODO storage DODO = DODOs[_id];

        id = _id;
        isReady = (DODO.cooldownEndBlock <= block.number);
        cooldownEndBlock = DODO.cooldownEndBlock;
        birthTime = DODO.birthTime;
        matronId = DODO.matronId;
        sireId = DODO.sireId;
        hatchingCost = _getBaseHatchingCost(DODO.generation);
        hatchingCostMultiplier = DODO.hatchingCostMultiplier;
        if (DODO.hatchCostMultiplierEndBlock <= block.number) {
            hatchingCostMultiplier = 1;
        }

        hatchCostMultiplierEndBlock = DODO.hatchCostMultiplierEndBlock;
        generation = DODO.generation;
        gene = DODO.gene;
        energy = DODO.energy;
        state = uint256(DODO.state);
    }

    /**
     * @dev Calculating hatching ALPA cost
     */
    function hatchingALPACost(uint256 _matronId, uint256 _sireId)
        external
        view
        returns (uint256)
    {
        return _hatchingALPACost(_matronId, _sireId, false);
    }

    /**
     * @dev Checks to see if a given egg passed cooldownEndBlock and ready to crack
     * @param _id DODO egg ID
     */

    function isReadyToCrack(uint256 _id) external view returns (bool) {
        DODO storage DODO = DODOs[_id];
        return
            (DODO.state == DODOGrowthState.EGG) &&
            (DODO.cooldownEndBlock <= uint64(block.number));
    }

    /* ========== EXTERNAL MUTATIVE FUNCTIONS  ========== */

    /**
     * Grants permission to another account to sire with one of your DODOs.
     * @param _addr The address that will be able to use sire for breeding.
     * @param _sireId a DODO _addr will be able to use for breeding as sire.
     */
    function grandPermissionToBreed(address _addr, uint256 _sireId)
        external
        override
    {
        require(
            isOwnerOf(msg.sender, _sireId),
            "CryptoDODO: You do not own sire DODO"
        );

        DODOAllowedToAddress.set(_sireId, _addr);
        emit GrantedToBreed(_sireId, _addr);
    }

    /**
     * check if `_addr` has permission to user DODO `_id` to breed with as sire.
     */
    function hasPermissionToBreedAsSire(address _addr, uint256 _id)
        external
        override
        view
        returns (bool)
    {
        if (isOwnerOf(_addr, _id)) {
            return true;
        }

        return DODOAllowedToAddress.get(_id) == _addr;
    }

    /**
     * Clear the permission on DODO for another user to use to breed.
     * @param _DODOId a DODO to clear permission .
     */
    function clearPermissionToBreed(uint256 _DODOId) external override {
        require(
            isOwnerOf(msg.sender, _DODOId),
            "CryptoDODO: You do not own this DODO"
        );

        DODOAllowedToAddress.remove(_DODOId);
    }

    /**
     * @dev Hatch an baby DODO egg with two DODO you own (_matronId and _sireId).
     * Requires a pre-payment of the fee given out to the first caller of crack()
     * @param _matronId The ID of the DODO acting as matron
     * @param _sireId The ID of the DODO acting as sire
     * @return The hatched DODO egg ID
     */
    function hatch(uint256 _matronId, uint256 _sireId)
        external
        override
        payable
        whenNotPaused
        nonReentrant
        returns (uint256)
    {
        address msgSender = msg.sender;

        // Checks for payment.
        require(
            msg.value >= autoCrackingFee,
            "CryptoDODO: Required autoCrackingFee not sent"
        );

        // Checks for ALPA payment
        require(
            alpa.allowance(msgSender, address(this)) >=
                _hatchingALPACost(_matronId, _sireId, true),
            "CryptoDODO: Required hetching ALPA fee not sent"
        );

        // Checks if matron and sire are valid mating pair
        require(
            _ownerPermittedToBreed(msgSender, _matronId, _sireId),
            "CryptoDODO: Invalid permission"
        );

        // Grab a reference to the potential matron
        DODO storage matron = DODOs[_matronId];

        // Make sure matron isn't pregnant, or in the middle of a siring cooldown
        require(
            _isReadyToHatch(matron),
            "CryptoDODO: Matron is not yet ready to hatch"
        );

        // Grab a reference to the potential sire
        DODO storage sire = DODOs[_sireId];

        // Make sure sire isn't pregnant, or in the middle of a siring cooldown
        require(
            _isReadyToHatch(sire),
            "CryptoDODO: Sire is not yet ready to hatch"
        );

        // Test that matron and sire are a valid mating pair.
        require(
            _isValidMatingPair(matron, _matronId, sire, _sireId),
            "CryptoDODO: Matron and Sire are not valid mating pair"
        );

        // All checks passed, DODO gets pregnant!
        return _hatchEgg(_matronId, _sireId);
    }

    /**
     * @dev egg is ready to crack and give life to baby DODO!
     * @param _id A DODO egg that's ready to crack.
     */
    function crack(uint256 _id) external override nonReentrant {
        // Grab a reference to the egg in storage.
        DODO storage egg = DODOs[_id];

        // Check that the egg is a valid DODO.
        require(egg.birthTime != 0, "CryptoDODO: not valid egg");
        require(
            egg.state == DODOGrowthState.EGG,
            "CryptoDODO: not a valid egg"
        );

        // Check that the matron is pregnant, and that its time has come!
        require(_isReadyToCrack(egg), "CryptoDODO: egg cant be cracked yet");

        // Grab a reference to the sire in storage.
        DODO storage matron = DODOs[egg.matronId];
        DODO storage sire = DODOs[egg.sireId];

        // Call the sooper-sekret gene mixing operation.
        (
            uint256 childGene,
            uint256 childEnergy,
            uint256 generationFactor
        ) = geneScience.mixGenes(
            matron.gene,
            sire.gene,
            egg.generation,
            uint256(egg.cooldownEndBlock).sub(1)
        );

        egg.gene = childGene;
        egg.energy = uint32(childEnergy);
        egg.state = DODOGrowthState.GROWN;
        egg.cooldownEndBlock = uint64(
            (newBornCoolDown.div(secondsPerBlock)).add(block.number)
        );
        egg.generationFactor = uint64(generationFactor);

        // Send the balance fee to the person who made birth happen.
        if (autoCrackingFee > 0) {
            msg.sender.transfer(autoCrackingFee);
        }

        // emit the born event
        emit BornSingle(_id, childGene, childEnergy);
    }

    /* ========== PRIVATE FUNCTION ========== */

    /**
     * @dev Recalculate the hatchingCostMultiplier for DODO after breed.
     * If hatchCostMultiplierEndBlock is less than current block number
     * reset hatchingCostMultiplier back to 2, otherwize multiply hatchingCostMultiplier by 2. Also update
     * hatchCostMultiplierEndBlock.
     */
    function _refreshHatchingMultiplier(DODO storage _DODO) private {
        if (_DODO.hatchCostMultiplierEndBlock < block.number) {
            _DODO.hatchingCostMultiplier = 2;
        } else {
            uint16 newMultiplier = _DODO.hatchingCostMultiplier * 2;
            if (newMultiplier > maxHatchCostMultiplier) {
                newMultiplier = maxHatchCostMultiplier;
            }

            _DODO.hatchingCostMultiplier = newMultiplier;
        }
        _DODO.hatchCostMultiplierEndBlock = uint64(
            (hatchingMultiplierCoolDown.div(secondsPerBlock)).add(block.number)
        );
    }

    function _ownerPermittedToBreed(
        address _sender,
        uint256 _matronId,
        uint256 _sireId
    ) private view returns (bool) {
        // owner must own matron, othersize not permitted
        if (!isOwnerOf(_sender, _matronId)) {
            return false;
        }

        // if owner owns sire, it's permitted
        if (isOwnerOf(_sender, _sireId)) {
            return true;
        }

        // if sire's owner has given permission to _sender to breed,
        // then it's permitted to breed
        if (DODOAllowedToAddress.contains(_sireId)) {
            return DODOAllowedToAddress.get(_sireId) == _sender;
        }

        return false;
    }

    /**
     * @dev Checks that a given DODO is able to breed. Requires that the
     * current cooldown is finished (for sires) and also checks that there is
     * no pending pregnancy.
     */
    function _isReadyToHatch(DODO storage _DODO)
        private
        view
        returns (bool)
    {
        return
            (_DODO.state == DODOGrowthState.GROWN) &&
            (_DODO.cooldownEndBlock < uint64(block.number));
    }

    /**
     * @dev Checks to see if a given DODO is pregnant and (if so) if the gestation
     * period has passed.
     */

    function _isReadyToCrack(DODO storage _egg) private view returns (bool) {
        return
            (_egg.state == DODOGrowthState.EGG) &&
            (_egg.cooldownEndBlock < uint64(block.number));
    }

    /**
     * @dev Calculating breeding ALPA cost for internal usage.
     */
    function _hatchingALPACost(
        uint256 _matronId,
        uint256 _sireId,
        bool _strict
    ) private view returns (uint256) {
        uint256 blockNum = block.number;
        if (!_strict) {
            blockNum = blockNum + 1;
        }

        DODO storage sire = DODOs[_sireId];
        uint256 sireHatchingBase = _getBaseHatchingCost(sire.generation);
        uint256 sireMultiplier = sire.hatchingCostMultiplier;
        if (sire.hatchCostMultiplierEndBlock < blockNum) {
            sireMultiplier = 1;
        }

        DODO storage matron = DODOs[_matronId];
        uint256 matronHatchingBase = _getBaseHatchingCost(matron.generation);
        uint256 matronMultiplier = matron.hatchingCostMultiplier;
        if (matron.hatchCostMultiplierEndBlock < blockNum) {
            matronMultiplier = 1;
        }

        return
            (sireHatchingBase.mul(sireMultiplier)).add(
                matronHatchingBase.mul(matronMultiplier)
            );
    }

    /**
     * @dev Internal utility function to initiate hatching egg, assumes that all breeding
     *  requirements have been checked.
     */
    function _hatchEgg(uint256 _matronId, uint256 _sireId)
        private
        returns (uint256)
    {
        // Transfer birthing ALPA fee to this contract
        uint256 alpaCost = _hatchingALPACost(_matronId, _sireId, true);

        uint256 devAmount = alpaCost.mul(devBreedingPercentage).div(100);
        uint256 stakingAmount = alpaCost.mul(100 - devBreedingPercentage).div(
            100
        );

        assert(alpa.transferFrom(msg.sender, devAddress, devAmount));
        assert(alpa.transferFrom(msg.sender, stakingAddress, stakingAmount));

        // Grab a reference to the DODOs from storage.
        DODO storage sire = DODOs[_sireId];
        DODO storage matron = DODOs[_matronId];

        // refresh hatching multiplier for both parents.
        _refreshHatchingMultiplier(sire);
        _refreshHatchingMultiplier(matron);

        // Determine the lower generation number of the two parents
        uint256 parentGen = matron.generation;
        if (sire.generation < matron.generation) {
            parentGen = sire.generation;
        }

        // child generation will be 1 larger than min of the two parents generation;
        uint256 childGen = parentGen.add(1);

        // Determine when the egg will be cracked
        uint256 cooldownEndBlock = (hatchingDuration.div(secondsPerBlock)).add(
            block.number
        );

        uint256 eggID = _createEgg(
            _matronId,
            _sireId,
            childGen,
            cooldownEndBlock,
            msg.sender
        );

        // Emit the hatched event.
        emit Hatched(eggID, _matronId, _sireId, cooldownEndBlock);

        return eggID;
    }

    /**
     * @dev Internal check to see if a given sire and matron are a valid mating pair.
     * @param _matron A reference to the DODO struct of the potential matron.
     * @param _matronId The matron's ID.
     * @param _sire A reference to the DODO struct of the potential sire.
     * @param _sireId The sire's ID
     */
    function _isValidMatingPair(
        DODO storage _matron,
        uint256 _matronId,
        DODO storage _sire,
        uint256 _sireId
    ) private view returns (bool) {
        // A Aapaca can't breed with itself
        if (_matronId == _sireId) {
            return false;
        }

        // DODO can't breed with their parents.
        if (_matron.matronId == _sireId || _matron.sireId == _sireId) {
            return false;
        }
        if (_sire.matronId == _matronId || _sire.sireId == _matronId) {
            return false;
        }

        return true;
    }

    /**
     * @dev openzeppelin ERC1155 Hook that is called before any token transfer
     * Clear any DODOAllowedToAddress associated to the DODO
     * that's been transfered
     */
    function _beforeTokenTransfer(
        address,
        address,
        address,
        uint256[] memory ids,
        uint256[] memory,
        bytes memory
    ) internal virtual override {
        for (uint256 i = 0; i < ids.length; i++) {
            if (DODOAllowedToAddress.contains(ids[i])) {
                DODOAllowedToAddress.remove(ids[i]);
            }
        }
    }
}
