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

// DODO Farm manages your LP and takes good care of you DODO!
contract DODOFarm is
    Ownable,
    ReentrancyGuard,
    ERC1155Receiver,
    CryptoDODOEnergyListener
{
    using SafeMath for uint256;
    using Math for uint256;
    using SafeERC20 for IERC20;
    using EnumerableMap for EnumerableMap.UintToAddressMap;

    /* ========== EVENTS ========== */

    event Deposit(address indexed user, uint256 amount);

    event Withdraw(address indexed user, uint256 amount);

    event EmergencyWithdraw(address indexed user, uint256 amount);

    /* ========== STRUCT ========== */

    // Info of each user.
    struct UserInfo {
        // How many LP tokens the user has provided.
        uint256 amount;
        // Reward debt. What has been paid so far
        uint256 rewardDebt;
        // DODO user transfered to DODOFarm to manage the LP assets
        uint256 DODOID;
        // DODO's energy
        uint256 DODOEnergy;
    }

    // Info of each pool.
    struct PoolInfo {
        // Address of LP token contract.
        IERC20 lpToken;
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

    // Energy if user does not have any DODO transfered to DODOFarm to manage the LP assets
    uint256 public constant EMPTY_DODO_ENERGY = 1;

    // farm pool info
    PoolInfo public poolInfo;

    // Info of each user that stakes LP tokens.
    mapping(address => UserInfo) public userInfo;

    // map that keep tracks of the DODO's original owner so contract knows where to send back when
    // users swapped or retrieved their DODOs
    EnumerableMap.UintToAddressMap private DODOOriginalOwner;

    uint256 public constant SAFE_MULTIPLIER = 1e16;

    /* ========== CONSTRUCTOR ========== */

    constructor(
        IBRDToken _BRD,
        ICryptoDODO _cryptoDODO,
        IBRDSupplier _supplier,
        IERC20 lpToken,
        uint256 _startBlock
    ) public {
        BRD = _BRD;
        cryptoDODO = _cryptoDODO;
        supplier = _supplier;
        poolInfo = PoolInfo({
            lpToken: lpToken,
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

        uint256 accBRDPerShare = poolInfo.accBRDPerShare;
        uint256 lpSupply = poolInfo.lpToken.balanceOf(address(this));

        if (block.number > poolInfo.lastRewardBlock && lpSupply != 0) {
            uint256 total = supplier.preview(
                address(this),
                poolInfo.lastRewardBlock
            );

            accBRDPerShare = accBRDPerShare.add(
                total.mul(SAFE_MULTIPLIER).div(poolInfo.accShare)
            );
        }
        return
            user
                .amount
                .mul(_safeUserDODOEnergy(user))
                .mul(accBRDPerShare)
                .div(SAFE_MULTIPLIER)
                .sub(user.rewardDebt);
    }

    /**
     * @dev Update reward variables of the given pool to be up-to-date.
     */
    function updatePool() public {
        if (block.number <= poolInfo.lastRewardBlock) {
            return;
        }

        uint256 lpSupply = poolInfo.lpToken.balanceOf(address(this));
        if (lpSupply == 0) {
            poolInfo.lastRewardBlock = block.number;
            return;
        }

        uint256 reward = supplier.distribute(poolInfo.lastRewardBlock);
        poolInfo.accBRDPerShare = poolInfo.accBRDPerShare.add(
            reward.mul(SAFE_MULTIPLIER).div(poolInfo.accShare)
        );

        poolInfo.lastRewardBlock = block.number;
    }

    /**
     * @dev Retrieve caller's DODO.
     */
    function retrieve() public nonReentrant {
        address sender = _msgSender();

        UserInfo storage user = userInfo[sender];
        require(user.DODOID != 0, "DODOFarm: you do not have any DODO");

        if (user.amount > 0) {
            updatePool();
            uint256 pending = user
                .amount
                .mul(user.DODOEnergy)
                .mul(poolInfo.accBRDPerShare)
                .div(SAFE_MULTIPLIER)
                .sub(user.rewardDebt);
            if (pending > 0) {
                _safeBRDTransfer(msg.sender, pending);
            }

            user.rewardDebt = user
                .amount
                .mul(EMPTY_DODO_ENERGY)
                .mul(poolInfo.accBRDPerShare)
                .div(SAFE_MULTIPLIER);

            poolInfo.accShare = poolInfo.accShare.sub(
                (user.DODOEnergy.sub(1)).mul(user.amount)
            );
        }

        uint256 prevDODOID = user.DODOID;
        user.DODOID = 0;
        user.DODOEnergy = 0;

        // Remove DODO id to original user mapping
        DODOOriginalOwner.remove(prevDODOID);

        cryptoDODO.safeTransferFrom(
            address(this),
            msg.sender,
            prevDODOID,
            1,
            ""
        );
    }

    /**
     * @dev Deposit LP tokens to DODOFarm for BRD allocation.
     */
    function deposit(uint256 _amount) public nonReentrant {
        updatePool();

        UserInfo storage user = userInfo[msg.sender];
        if (user.amount > 0) {
            uint256 pending = user
                .amount
                .mul(_safeUserDODOEnergy(user))
                .mul(poolInfo.accBRDPerShare)
                .div(SAFE_MULTIPLIER)
                .sub(user.rewardDebt);
            if (pending > 0) {
                _safeBRDTransfer(msg.sender, pending);
            }
        }

        if (_amount > 0) {
            poolInfo.lpToken.safeTransferFrom(
                address(msg.sender),
                address(this),
                _amount
            );
            user.amount = user.amount.add(_amount);
            poolInfo.accShare = poolInfo.accShare.add(
                _safeUserDODOEnergy(user).mul(_amount)
            );
        }

        user.rewardDebt = user
            .amount
            .mul(_safeUserDODOEnergy(user))
            .mul(poolInfo.accBRDPerShare)
            .div(SAFE_MULTIPLIER);
        emit Deposit(msg.sender, _amount);
    }

    /**
     * @dev Withdraw LP tokens from DODOFarm.
     */
    function withdraw(uint256 _amount) public nonReentrant {
        UserInfo storage user = userInfo[msg.sender];
        require(user.amount >= _amount, "DODOFarm: invalid amount");

        updatePool();
        uint256 pending = user
            .amount
            .mul(_safeUserDODOEnergy(user))
            .mul(poolInfo.accBRDPerShare)
            .div(SAFE_MULTIPLIER)
            .sub(user.rewardDebt);

        if (pending > 0) {
            _safeBRDTransfer(msg.sender, pending);
        }
        if (_amount > 0) {
            user.amount = user.amount.sub(_amount);
            poolInfo.lpToken.safeTransfer(address(msg.sender), _amount);
            poolInfo.accShare = poolInfo.accShare.sub(
                _safeUserDODOEnergy(user).mul(_amount)
            );
        }

        user.rewardDebt = user
            .amount
            .mul(_safeUserDODOEnergy(user))
            .mul(poolInfo.accBRDPerShare)
            .div(SAFE_MULTIPLIER);
        emit Withdraw(msg.sender, _amount);
    }

    // Withdraw without caring about rewards.
    // EMERGENCY ONLY.
    function emergencyWithdraw() public {
        UserInfo storage user = userInfo[msg.sender];
        require(user.amount > 0, "DODOFarm: insufficient balance");

        uint256 amount = user.amount;
        user.amount = 0;
        user.rewardDebt = 0;
        poolInfo.lpToken.safeTransfer(address(msg.sender), amount);
        emit EmergencyWithdraw(msg.sender, amount);
    }

    /* ========== PRIVATE ========== */

    function _safeUserDODOEnergy(UserInfo storage info)
        private
        view
        returns (uint256)
    {
        if (info.DODOEnergy == 0) {
            return EMPTY_DODO_ENERGY;
        }
        return info.DODOEnergy;
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

    /* ========== ERC1155Receiver ========== */

    /**
     * @dev onERC1155Received implementation per IERC1155Receiver spec
     */
    function onERC1155Received(
        address,
        address _from,
        uint256 _id,
        uint256,
        bytes calldata
    ) external override nonReentrant returns (bytes4) {
        require(
            msg.sender == address(cryptoDODO),
            "DODOFarm: received DODO from unauthenticated contract"
        );

        require(_id != 0, "DODOFarm: invalid DODO");

        UserInfo storage user = userInfo[_from];

        // Fetch DODO energy
        (, , , , , , , , , , , uint256 energy, ) = cryptoDODO.getDODO(_id);
        require(energy > 0, "DODOFarm: invalid DODO energy");

        if (user.amount > 0) {
            updatePool();

            uint256 pending = user
                .amount
                .mul(_safeUserDODOEnergy(user))
                .mul(poolInfo.accBRDPerShare)
                .div(SAFE_MULTIPLIER)
                .sub(user.rewardDebt);
            if (pending > 0) {
                _safeBRDTransfer(_from, pending);
            }
            // Update user reward debt with new energy
            user.rewardDebt = user
                .amount
                .mul(energy)
                .mul(poolInfo.accBRDPerShare)
                .div(SAFE_MULTIPLIER);

            poolInfo.accShare = poolInfo
                .accShare
                .add(energy.mul(user.amount))
                .sub(_safeUserDODOEnergy(user).mul(user.amount));
        }

        // update user global
        uint256 prevDODOID = user.DODOID;
        user.DODOID = _id;
        user.DODOEnergy = energy;

        // keep track of DODO owner
        DODOOriginalOwner.set(_id, _from);

        // Give original owner the right to breed
        cryptoDODO.grandPermissionToBreed(_from, _id);

        if (prevDODOID != 0) {
            // Transfer DODO back to owner
            cryptoDODO.safeTransferFrom(
                address(this),
                _from,
                prevDODOID,
                1,
                ""
            );
        }

        return
            bytes4(
                keccak256(
                    "onERC1155Received(address,address,uint256,uint256,bytes)"
                )
            );
    }

    /**
     * @dev onERC1155BatchReceived implementation per IERC1155Receiver spec
     * User should not send using batch.
     */
    function onERC1155BatchReceived(
        address,
        address,
        uint256[] memory,
        uint256[] memory,
        bytes memory
    ) external override returns (bytes4) {
        require(
            false,
            "DODOFarm: only supports transfer single DODO at a time (e.g safeTransferFrom)"
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
        uint256,
        uint256 _newEnergy
    ) external override {
        require(
            msg.sender == address(cryptoDODO),
            "DODOFarm: received DODO from unauthenticated contract"
        );

        require(
            DODOOriginalOwner.contains(_id),
            "DODOFarm: original owner not found"
        );

        address originalOwner = DODOOriginalOwner.get(_id);
        UserInfo storage user = userInfo[originalOwner];

        if (user.amount > 0) {
            updatePool();

            uint256 pending = user
                .amount
                .mul(_safeUserDODOEnergy(user))
                .mul(poolInfo.accBRDPerShare)
                .div(SAFE_MULTIPLIER)
                .sub(user.rewardDebt);

            if (pending > 0) {
                _safeBRDTransfer(originalOwner, pending);
            }

            // Update user reward debt with new energy
            user.rewardDebt = user
                .amount
                .mul(_newEnergy)
                .mul(poolInfo.accBRDPerShare)
                .div(SAFE_MULTIPLIER);

            poolInfo.accShare = poolInfo
                .accShare
                .add(_newEnergy.mul(user.amount))
                .sub(_safeUserDODOEnergy(user).mul(user.amount));
        }

        // update DODO energy
        user.DODOEnergy = _newEnergy;
    }
}
