// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin/contracts/utils/EnumerableSet.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/math/Math.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import "../interfaces/IBRDToken.sol";
import "../interfaces/IBRDSupplier.sol";

contract BRDSupplier is Ownable, IBRDSupplier, ReentrancyGuard {
    using SafeMath for uint256;
    using Math for uint256;
    using EnumerableSet for EnumerableSet.AddressSet;

    // The BRD ERC20 token
    IBRDToken public BRD;

    // Set of address that are approved consumer
    EnumerableSet.AddressSet private approvedConsumers;

    // map of consumer address to consumer info
    mapping(address => ConsumerInfo) public consumerInfo;

    // Total allocation poitns. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;

    // number of BRD tokens created per block.
    uint256 public BRDPerBlock;

    // dev address.
    address public devAddr;

    // community address.
    address public communityAddr;

    // Info of each consumer.
    struct ConsumerInfo {
        // Address of consumer.
        address consumer;
        // How many allocation points assigned to this consumer
        uint256 allocPoint;
        // Last block number that BRDs distribution occurs.
        uint256 lastDistributeBlock;
    }

    constructor(
        IBRDToken _BRD,
        uint256 _BRDPerBlock,
        address _devAddr,
        address _communityAddr
    ) public {
        BRD = _BRD;
        BRDPerBlock = _BRDPerBlock;
        devAddr = _devAddr;
        communityAddr = _communityAddr;
    }

    function isApprovedConsumer(address _consumer) public view returns (bool) {
        return approvedConsumers.contains(_consumer);
    }

    function distribute(uint256 _since)
        public
        override
        onlyApprovedConsumer
        nonReentrant
        returns (uint256)
    {
        address sender = _msgSender();

        ConsumerInfo storage consumer = consumerInfo[sender];
        uint256 multiplier = _getMultiplier(
            consumer.lastDistributeBlock,
            block.number,
            _since
        );
        if (multiplier == 0) {
            return 0;
        }

        consumer.lastDistributeBlock = block.number;
        uint256 amount = multiplier
            .mul(BRDPerBlock)
            .mul(consumer.allocPoint)
            .div(totalAllocPoint);

        // 10% of total reward goes to dev
        uint256 devReward = amount.div(10);
        BRD.mint(devAddr, devReward);

        // 10% of total reward goes to community
        uint256 communityReward = amount.div(10);
        BRD.mint(communityAddr, communityReward);

        //  rest goes to consumer
        uint256 consumerReward = amount.sub(devReward).sub(communityReward);
        BRD.mint(sender, consumerReward);

        return consumerReward;
    }

    function preview(address _consumer, uint256 _since)
        public
        override
        view
        returns (uint256)
    {
        require(
            approvedConsumers.contains(_consumer),
            "BRDSupplier: consumer isn't approved"
        );

        ConsumerInfo storage consumer = consumerInfo[_consumer];
        uint256 multiplier = _getMultiplier(
            consumer.lastDistributeBlock,
            block.number,
            _since
        );
        if (multiplier == 0) {
            return 0;
        }

        uint256 amount = multiplier
            .mul(BRDPerBlock)
            .mul(consumer.allocPoint)
            .div(totalAllocPoint);

        // 80% of token goes to consumer
        return amount.mul(8).div(10);
    }

    // Return reward multiplier over the given _from to _to block.
    function _getMultiplier(
        uint256 _from,
        uint256 _to,
        uint256 _since
    ) private pure returns (uint256) {
        return _to.sub(_from.max(_since));
    }

    /* ========== OWNER ============= */

    /**
     * @dev Add a new consumer. Can only be called by the owner
     */
    function add(
        uint256 _allocPoint,
        address _consumer,
        uint256 _startBlock
    ) public onlyOwner {
        approvedConsumers.add(_consumer);
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        consumerInfo[_consumer] = ConsumerInfo({
            consumer: _consumer,
            allocPoint: _allocPoint,
            lastDistributeBlock: _startBlock
        });
    }

    /**
     * @dev Removes a consumer. Can only be called by the owner
     */
    function remove(address _consumer) public onlyOwner {
        require(
            approvedConsumers.contains(_consumer),
            "BRDSupplier: consumer isn't approved"
        );

        approvedConsumers.remove(_consumer);

        totalAllocPoint = totalAllocPoint.sub(
            consumerInfo[_consumer].allocPoint
        );

        delete consumerInfo[_consumer];
    }

    /**
     * @dev Update the given consumer's BRD allocation point. Can only be called by the owner.
     */
    function set(address _consumer, uint256 _allocPoint) public onlyOwner {
        require(
            approvedConsumers.contains(_consumer),
            "BRDSupplier: consumer isn't approved"
        );

        totalAllocPoint = totalAllocPoint.add(_allocPoint).sub(
            consumerInfo[_consumer].allocPoint
        );
        consumerInfo[_consumer].allocPoint = _allocPoint;
    }

    // Transfer BRD owner to `_owner`
    // EMERGENCY ONLY
    function setBRDOwner(address _owner) external onlyOwner {
        Ownable(address(BRD)).transferOwnership(_owner);
    }

    // Update number of BRD to mint per block
    function setBRDPerBlock(uint256 _BRDPerBlock) external onlyOwner {
        BRDPerBlock = _BRDPerBlock;
    }

    // Update dev address by the previous dev.
    function setDevAddr(address _devAddr) external {
        require(devAddr == _msgSender(), "BRDSupplier: unauthorized");
        devAddr = _devAddr;
    }

    // Update community pool addr address by the previous dev.
    function setCommunityAddr(address _communityAddr) external {
        require(communityAddr == _msgSender(), "BRDSupplier: unauthorized");
        communityAddr = _communityAddr;
    }

    /* ========== MODIFIER ========== */

    modifier onlyApprovedConsumer() {
        require(
            approvedConsumers.contains(_msgSender()),
            "BRDSupplier: unauthorized"
        );
        _;
    }
}
