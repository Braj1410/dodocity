// SPDX-License-Identifier: MIT

pragma solidity =0.6.12;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/EnumerableMap.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "../interfaces/IGeneScience.sol";

contract DODOBase is Ownable {
    using SafeMath for uint256;

    /* ========== ENUM ========== */

    /**
     * @dev DODO can be in one of the two state:
     *
     * EGG - When two DODO breed with each other, DODO EGG is created.
     *       `gene` and `energy` are both 0 and will be assigned when egg is cracked
     *
     * GROWN - When egg is cracked and DODO is born! `gene` and `energy` are determined
     *         in this state.
     */
    enum DODOGrowthState {EGG, GROWN}

    /* ========== PUBLIC STATE VARIABLES ========== */

    /**
     * @dev payment required to use cracked if it's done automatically
     * assigning to 0 indicate cracking action is not automatic
     */
    uint256 public autoCrackingFee = 0;

    /**
     * @dev Base breeding ALPA fee
     */
    uint256 public baseHatchingFee = 10e18; // 10 ALPA

    /**
     * @dev ALPA ERC20 contract address
     */
    IERC20 public alpa;

    /**
     * @dev 10% of the breeding ALPA fee goes to `devAddress`
     */
    address public devAddress;

    /**
     * @dev 90% of the breeding ALPA fee goes to `stakingAddress`
     */
    address public stakingAddress;

    /**
     * @dev number of percentage breeding ALPA fund goes to devAddress
     * dev percentage = devBreedingPercentage / 100
     * staking percentage = (100 - devBreedingPercentage) / 100
     */
    uint256 public devBreedingPercentage = 10;

    /**
     * @dev An approximation of currently how many seconds are in between blocks.
     */
    uint256 public secondsPerBlock = 15;

    /**
     * @dev amount of time a new born DODO needs to wait before participating in breeding activity.
     */
    uint256 public newBornCoolDown = uint256(1 days);

    /**
     * @dev amount of time an egg needs to wait to be cracked
     */
    uint256 public hatchingDuration = uint256(5 minutes);

    /**
     * @dev when two DODO just bred, the breeding multiplier will doubled to control
     * DODO's population. This is the amount of time each parent must wait for the
     * breeding multiplier to reset back to 1
     */
    uint256 public hatchingMultiplierCoolDown = uint256(6 hours);

    /**
     * @dev hard cap on the maximum hatching cost multiplier it can reach to
     */
    uint16 public maxHatchCostMultiplier = 16;

    /**
     * @dev Gen0 generation factor
     */
    uint64 public constant GEN0_GENERATION_FACTOR = 10;

    /**
     * @dev maximum gen-0 DODO energy. This is to prevent contract owner from
     * creating arbitrary energy for gen-0 DODO
     */
    uint32 public constant MAX_GEN0_ENERGY = 3600;

    /**
     * @dev hatching fee increase with higher alpa generation
     */
    uint256 public generationHatchingFeeMultiplier = 2;

    /**
     * @dev gene science contract address for genetic combination algorithm.
     */
    IGeneScience public geneScience;

    /* ========== INTERNAL STATE VARIABLES ========== */

    /**
     * @dev An array containing the DODO struct for all DODOs in existence. The ID
     * of each DODO is the index into this array.
     */
    DODO[] internal DODOs;

    /**
     * @dev mapping from DODOIDs to an address where DODO owner approved address to use
     * this alpca for breeding. addrss can breed with this cat multiple times without limit.
     * This will be resetted everytime someone transfered the DODO.
     */
    EnumerableMap.UintToAddressMap internal DODOAllowedToAddress;

    /* ========== DODO STRUCT ========== */

    /**
     * @dev Everything about your DODO is stored in here. Each DODO's appearance
     * is determined by the gene. The energy associated with each DODO is also
     * related to the gene
     */
    struct DODO {
        // TheaDODO genetic code.
        uint256 gene;
        // the DODO energy level
        uint32 energy;
        // The timestamp from the block when this DODO came into existence.
        uint64 birthTime;
        // The minimum timestamp DODO needs to wait to avoid hatching multiplier
        uint64 hatchCostMultiplierEndBlock;
        // hatching cost multiplier
        uint16 hatchingCostMultiplier;
        // The ID of the parents of this DODO, set to 0 for gen0 DODO.
        uint32 matronId;
        uint32 sireId;
        // The "generation number" of this DODO. The generation number of an DODOs
        // is the smaller of the two generation numbers of their parents, plus one.
        uint16 generation;
        // The minimum timestamp new born DODO needs to wait to hatch egg.
        uint64 cooldownEndBlock;
        // The generation factor buffs DODO energy level
        uint64 generationFactor;
        // defines current DODO state
        DODOGrowthState state;
    }

    /* ========== VIEW ========== */

    function getTotalDODO() external view returns (uint256) {
        return DODOs.length;
    }

    function _getBaseHatchingCost(uint256 _generation)
        internal
        view
        returns (uint256)
    {
        return
            baseHatchingFee.add(
                _generation.mul(generationHatchingFeeMultiplier).mul(1e18)
            );
    }

    /* ========== OWNER MUTATIVE FUNCTION ========== */

    /**
     * @param _hatchingDuration hatching duration
     */
    function setHatchingDuration(uint256 _hatchingDuration) external onlyOwner {
        hatchingDuration = _hatchingDuration;
    }

    /**
     * @param _stakingAddress staking address
     */
    function setStakingAddress(address _stakingAddress) external onlyOwner {
        stakingAddress = _stakingAddress;
    }

    /**
     * @param _devAddress dev address
     */
    function setDevAddress(address _devAddress) external onlyDev {
        devAddress = _devAddress;
    }

    /**
     * @param _maxHatchCostMultiplier max hatch cost multiplier
     */
    function setMaxHatchCostMultiplier(uint16 _maxHatchCostMultiplier)
        external
        onlyOwner
    {
        maxHatchCostMultiplier = _maxHatchCostMultiplier;
    }

    /**
     * @param _devBreedingPercentage base generation factor
     */
    function setDevBreedingPercentage(uint256 _devBreedingPercentage)
        external
        onlyOwner
    {
        require(
            devBreedingPercentage <= 100,
            "CryptoDODO: invalid breeding percentage - must be between 0 and 100"
        );
        devBreedingPercentage = _devBreedingPercentage;
    }

    /**
     * @param _generationHatchingFeeMultiplier multiplier
     */
    function setGenerationHatchingFeeMultiplier(
        uint256 _generationHatchingFeeMultiplier
    ) external onlyOwner {
        generationHatchingFeeMultiplier = _generationHatchingFeeMultiplier;
    }

    /**
     * @param _baseHatchingFee base birthing
     */
    function setBaseHatchingFee(uint256 _baseHatchingFee) external onlyOwner {
        baseHatchingFee = _baseHatchingFee;
    }

    /**
     * @param _newBornCoolDown new born cool down
     */
    function setNewBornCoolDown(uint256 _newBornCoolDown) external onlyOwner {
        newBornCoolDown = _newBornCoolDown;
    }

    /**
     * @param _hatchingMultiplierCoolDown base birthing
     */
    function setHatchingMultiplierCoolDown(uint256 _hatchingMultiplierCoolDown)
        external
        onlyOwner
    {
        hatchingMultiplierCoolDown = _hatchingMultiplierCoolDown;
    }

    /**
     * @dev update how many seconds per blocks are currently observed.
     * @param _secs number of seconds
     */
    function setSecondsPerBlock(uint256 _secs) external onlyOwner {
        secondsPerBlock = _secs;
    }

    /**
     * @dev only owner can update autoCrackingFee
     */
    function setAutoCrackingFee(uint256 _autoCrackingFee) external onlyOwner {
        autoCrackingFee = _autoCrackingFee;
    }

    /**
     * @dev owner can upgrading gene science
     */
    function setGeneScience(IGeneScience _geneScience) external onlyOwner {
        require(
            _geneScience.isDODOGeneScience(),
            "CryptoDODO: invalid gene science contract"
        );

        // Set the new contract address
        geneScience = _geneScience;
    }

    /**
     * @dev owner can update ALPA erc20 token location
     */
    function setAlpaContract(IERC20 _alpa) external onlyOwner {
        alpa = _alpa;
    }

    /* ========== MODIFIER ========== */

    /**
     * @dev Throws if called by any account other than the dev.
     */
    modifier onlyDev() {
        require(
            devAddress == _msgSender(),
            "CryptoDODO: caller is not the dev"
        );
        _;
    }
}
