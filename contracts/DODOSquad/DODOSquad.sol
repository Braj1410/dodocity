// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC1155/ERC1155Receiver.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/utils/EnumerableMap.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/math/Math.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "../interfaces/IBRDToken.sol";
import "../interfaces/IBRDSupplier.sol";
import "../interfaces/ICryptoDODO.sol";
import "../interfaces/CryptoDODOEnergyListener.sol";

// DODO Squad manages your you DODOs
contract DODOSquad is
    Ownable,
    ReentrancyGuard,
    ERC1155Receiver,
    CryptoDODOEnergyListener
{
    using SafeMath for uint256;
    using Math for uint256;
    using SafeERC20 for IERC20;
    using EnumerableMap for EnumerableMap.UintToAddressMap;

    // Info of each user.
    struct UserInfo {
        // Reward debt
        uint256 rewardDebt;
        // share
        uint256 share;
        // number of DODOs in this squad
        uint256 numDODOs;
        // sum of DODO energy
        uint256 sumEnergy;
    }

    // Info of Reward.
    struct RewardInfo {
        // Last block number that BRDs distribution occurs.
        uint256 lastRewardBlock;
        // Accumulated BRDs per share. Share is determined by LP deposit and total DODO's energy
        uint256 accBRDPerShare;
        // Accumulated Share
        uint256 accShare;
    }

    /* ========== STATES ========== */

    // The BRD ERC20 token
    IBRDToken public BRD;

    // Crypto DODO contract
    ICryptoDODO public cryptoDODO;

    // BRD Supplier
    IBRDSupplier public supplier;

    // farm pool info
    RewardInfo public rewardInfo;

    uint256 public maxDODOSquadCount = 20;

    // Info of each user.
    mapping(address => UserInfo) public userInfo;

    // map that keep tracks of the DODO's original owner so contract knows where to send back when
    // users retrieves their DODOs
    EnumerableMap.UintToAddressMap private DODOOriginalOwner;

    uint256 public constant SAFE_MULTIPLIER = 1e16;

    /* ========== CONSTRUCTOR ========== */

    constructor(
        IBRDToken _BRD,
        ICryptoDODO _cryptoDODO,
        IBRDSupplier _supplier,
        uint256 _startBlock
    ) public {
        BRD = _BRD;
        cryptoDODO = _cryptoDODO;
        supplier = _supplier;
        rewardInfo = RewardInfo({
            lastRewardBlock: block.number.max(_startBlock),
            accBRDPerShare: 0,
            accShare: 0
        });
    }

    /* ========== PUBLIC ========== */

    /**
     * @dev View `_user` pending BRDs
     */
    function pendingBRD(address _user) external view returns (uint256) {
        UserInfo storage user = userInfo[_user];

        uint256 accBRDPerShare = rewardInfo.accBRDPerShare;

        if (
            block.number > rewardInfo.lastRewardBlock &&
            rewardInfo.accShare != 0
        ) {
            uint256 total = supplier.preview(
                address(this),
                rewardInfo.lastRewardBlock
            );

            accBRDPerShare = accBRDPerShare.add(
                total.mul(SAFE_MULTIPLIER).div(rewardInfo.accShare)
            );
        }

        return
            user.share.mul(accBRDPerShare).div(SAFE_MULTIPLIER).sub(
                user.rewardDebt
            );
    }

    /**
     * @dev Update reward variables of the given pool to be up-to-date.
     */
    function updatePool() public {
        if (block.number <= rewardInfo.lastRewardBlock) {
            return;
        }

        if (rewardInfo.accShare == 0) {
            rewardInfo.lastRewardBlock = block.number;
            return;
        }

        uint256 reward = supplier.distribute(rewardInfo.lastRewardBlock);
        rewardInfo.accBRDPerShare = rewardInfo.accBRDPerShare.add(
            reward.mul(SAFE_MULTIPLIER).div(rewardInfo.accShare)
        );

        rewardInfo.lastRewardBlock = block.number;
    }

    /**
     * @dev Retrieve caller's DODOs
     */
    function retrieve(uint256[] memory _ids) public nonReentrant {
        require(_ids.length > 0, "DODOSquad: invalid argument");

        address sender = msg.sender;
        UserInfo storage user = userInfo[sender];
        (
            uint256 share,
            uint256 numDODOs,
            uint256 sumEnergy
        ) = _calculateDeletion(sender, user, _ids);

        updatePool();

        uint256 pending = user
            .share
            .mul(rewardInfo.accBRDPerShare)
            .div(SAFE_MULTIPLIER)
            .sub(user.rewardDebt);
        if (pending > 0) {
            _safeBRDTransfer(sender, pending);
        }

        // Update user reward debt with new share
        user.rewardDebt = share.mul(rewardInfo.accBRDPerShare).div(
            SAFE_MULTIPLIER
        );

        // Update reward info accumulated share
        rewardInfo.accShare = rewardInfo.accShare.add(share).sub(user.share);

        user.share = share;
        user.numDODOs = numDODOs;
        user.sumEnergy = sumEnergy;

        for (uint256 i = 0; i < _ids.length; i++) {
            DODOOriginalOwner.remove(_ids[i]);
            cryptoDODO.safeTransferFrom(
                address(this),
                sender,
                _ids[i],
                1,
                ""
            );
        }
    }

    /**
     * @dev Claim user reward
     */
    function claim() public nonReentrant {
        updatePool();
        address sender = msg.sender;

        UserInfo storage user = userInfo[sender];
        if (user.sumEnergy > 0) {
            uint256 pending = user
                .share
                .mul(rewardInfo.accBRDPerShare)
                .div(SAFE_MULTIPLIER)
                .sub(user.rewardDebt);

            if (pending > 0) {
                _safeBRDTransfer(sender, pending);
            }

            user.rewardDebt = user.share.mul(rewardInfo.accBRDPerShare).div(
                SAFE_MULTIPLIER
            );
        }
    }

    /* ========== ERC1155Receiver ========== */

    /**
     * @dev onERC1155Received implementation per IERC1155Receiver spec
     */
    function onERC1155Received(
        address,
        address _from,
        uint256 _id,
        uint256,
        bytes memory
    ) external override nonReentrant fromCryptoDODO returns (bytes4) {
        UserInfo storage user = userInfo[_from];
        uint256[] memory ids = _asSingletonArray(_id);
        (
            uint256 share,
            uint256 numDODOs,
            uint256 sumEnergy
        ) = _calculateAddition(user, ids);

        updatePool();

        if (user.sumEnergy > 0) {
            uint256 pending = user
                .share
                .mul(rewardInfo.accBRDPerShare)
                .div(SAFE_MULTIPLIER)
                .sub(user.rewardDebt);
            if (pending > 0) {
                _safeBRDTransfer(_from, pending);
            }
        }

        // Update user reward debt with new share
        user.rewardDebt = share.mul(rewardInfo.accBRDPerShare).div(
            SAFE_MULTIPLIER
        );

        // Update reward info accumulated share
        rewardInfo.accShare = rewardInfo.accShare.add(share).sub(user.share);

        user.share = share;
        user.numDODOs = numDODOs;
        user.sumEnergy = sumEnergy;

        // Give original owner the right to breed
        cryptoDODO.grandPermissionToBreed(_from, _id);

        // store original owner
        DODOOriginalOwner.set(_id, _from);

        return
            bytes4(
                keccak256(
                    "onERC1155Received(address,address,uint256,uint256,bytes)"
                )
            );
    }

    /**
     * @dev onERC1155BatchReceived implementation per IERC1155Receiver spec
     */
    function onERC1155BatchReceived(
        address,
        address _from,
        uint256[] memory _ids,
        uint256[] memory,
        bytes memory
    ) external override nonReentrant fromCryptoDODO returns (bytes4) {
        UserInfo storage user = userInfo[_from];
        (
            uint256 share,
            uint256 numDODOs,
            uint256 sumEnergy
        ) = _calculateAddition(user, _ids);

        updatePool();

        if (user.sumEnergy > 0) {
            uint256 pending = user
                .share
                .mul(rewardInfo.accBRDPerShare)
                .div(SAFE_MULTIPLIER)
                .sub(user.rewardDebt);
            if (pending > 0) {
                _safeBRDTransfer(_from, pending);
            }
        }

        // Update user reward debt with new share
        user.rewardDebt = share.mul(rewardInfo.accBRDPerShare).div(
            SAFE_MULTIPLIER
        );

        // Update reward info accumulated share
        rewardInfo.accShare = rewardInfo.accShare.add(share).sub(user.share);

        user.share = share;
        user.numDODOs = numDODOs;
        user.sumEnergy = sumEnergy;

        // Give original owner the right to breed
        for (uint256 i = 0; i < _ids.length; i++) {
            // store original owner
            DODOOriginalOwner.set(_ids[i], _from);

            // Give original owner the right to breed
            cryptoDODO.grandPermissionToBreed(_from, _ids[i]);
        }

        return
            bytes4(
                keccak256(
                    "onERC1155BatchReceived(address,address,uint256[],uint256[],bytes)"
                )
            );
    }

    /* ========== ICryptoDODOEnergyListener ========== */

    /**
        @dev Handles the DODO energy change callback.
        @param _id The id of the DODO which the energy changed
        @param _newEnergy The new DODO energy it changed to
    */
    function onCryptoDODOEnergyChanged(
        uint256 _id,
        uint256 _oldEnergy,
        uint256 _newEnergy
    ) external override fromCryptoDODO ownsDODO(_id) {
        address from = DODOOriginalOwner.get(_id);
        UserInfo storage user = userInfo[from];

        uint256 sumEnergy = user.sumEnergy.add(_newEnergy).sub(_oldEnergy);
        uint256 share = sumEnergy.mul(sumEnergy).div(user.numDODOs);

        updatePool();

        if (user.sumEnergy > 0) {
            uint256 pending = user
                .share
                .mul(rewardInfo.accBRDPerShare)
                .div(SAFE_MULTIPLIER)
                .sub(user.rewardDebt);
            if (pending > 0) {
                _safeBRDTransfer(from, pending);
            }
        }
        // Update user reward debt with new share
        user.rewardDebt = share.mul(rewardInfo.accBRDPerShare).div(
            SAFE_MULTIPLIER
        );

        // Update reward info accumulated share
        rewardInfo.accShare = rewardInfo.accShare.add(share).sub(user.share);

        user.share = share;
        user.sumEnergy = sumEnergy;
    }

    /* ========== PRIVATE ========== */

    /**
     * @dev given user and array of DODOs ids, it validate the DODOs
     * and calculates the user share, numDODOs, and sumEnergy after the addition
     */
    function _calculateAddition(UserInfo storage _user, uint256[] memory _ids)
        private
        view
        returns (
            uint256 share,
            uint256 numDODOs,
            uint256 sumEnergy
        )
    {
        require(
            _user.numDODOs + _ids.length <= maxDODOSquadCount,
            "DODOSquad: Max DODO reached"
        );
        numDODOs = _user.numDODOs + _ids.length;
        sumEnergy = _user.sumEnergy;

        for (uint256 i = 0; i < _ids.length; i++) {
            uint256 id = _ids[i];
            require(id != 0, "DODOSquad: invalid DODO");

            // Fetch DODO energy and state
            (, , , , , , , , , , , uint256 energy, uint256 state) = cryptoDODO
                .getDODO(id);
            require(state == 1, "DODOFarm: invalid DODO state");
            require(energy > 0, "DODOFarm: invalid DODO energy");
            sumEnergy = sumEnergy.add(energy);
        }

        share = sumEnergy.mul(sumEnergy).div(numDODOs);
    }

    function _calculateDeletion(
        address owner,
        UserInfo storage _user,
        uint256[] memory _ids
    )
        private
        view
        returns (
            uint256 share,
            uint256 numDODOs,
            uint256 sumEnergy
        )
    {
        numDODOs = _user.numDODOs.sub(_ids.length);
        sumEnergy = _user.sumEnergy;

        for (uint256 i = 0; i < _ids.length; i++) {
            uint256 id = _ids[i];
            require(
                DODOOriginalOwner.get(id) == owner,
                "DODOFarm: original owner not found"
            );

            // Fetch DODO energy and state
            (, , , , , , , , , , , uint256 energy, ) = cryptoDODO.getDODO(
                id
            );
            sumEnergy = sumEnergy.sub(energy);
        }

        if (numDODOs > 0) {
            share = sumEnergy.mul(sumEnergy).div(numDODOs);
        }
    }

    function _asSingletonArray(uint256 element)
        private
        pure
        returns (uint256[] memory)
    {
        uint256[] memory array = new uint256[](1);
        array[0] = element;

        return array;
    }

    // Safe BRD transfer function, just in case if rounding error causes pool to not have enough BRDs.
    function _safeBRDTransfer(address _to, uint256 _amount) private {
        uint256 BRDBal = BRD.balanceOf(address(this));
        if (_amount > BRDBal) {
            BRD.transfer(_to, BRDBal);
        } else {
            BRD.transfer(_to, _amount);
        }
    }

    /* ========== Owner ========== */

    function setMaxDODOSquadCount(uint256 _count) public onlyOwner {
        maxDODOSquadCount = _count;
    }

    /* ========== MODIFIER ========== */

    modifier fromCryptoDODO() {
        require(
            msg.sender == address(cryptoDODO),
            "DODOFarm: received DODO from unauthenticated contract"
        );
        _;
    }

    modifier ownsDODO(uint256 _id) {
        require(
            DODOOriginalOwner.contains(_id),
            "DODOFarm: original owner not found"
        );
        _;
    }
}
