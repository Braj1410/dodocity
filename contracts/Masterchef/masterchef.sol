// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol"; 
import "@openzeppelin/contracts/token/ERC1155/ERC1155Receiver.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/utils/EnumerableSet.sol";
import "@openzeppelin/contracts/math/SafeMath.sol"; 
import "@openzeppelin/contracts/access/Ownable.sol";
import "../interfaces/IBRDToken.sol";
import "../interfaces/ICryptoDODO.sol";

contract MasterChef is Ownable, ERC1155Receiver {
  using SafeMath for uint256; using SafeERC20 for IERC20;
  /* ========== EVENTS ========== */
  event Deposit(address indexed user, uint256 indexed pid, uint256 amount);// knownsec Deposit event
  event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);// knownsec Withdrawal event
   /* ========== STRUCT ========== */
   // Info of each user. 
  struct UserInfo {// knownsec User structure, account balance, income // How many LP tokens the user has provided. 
 
    uint256 amount; // Reward debt. What have been paid so far 
    uint256 rewardDebt; 
     
   }
  struct UserGlobalInfo {// knownsec User global parameters, DODOID, income 
   // DODO associated 
   uint256 DODOID;
   // DODO energy 
   uint256 DODOEnergy; 
     
   }
   // Info of each pool. 
   struct PoolInfo {
       // knownsec Pool information 
       // Address of LP token contract. 
       IERC20 lpToken; 
       // How many allocation points assigned to this pool. BRDs to distribute per block. 
       uint256 allocPoint; 
       // Last block number that BRDs distribution occurs.
       uint256 lastRewardBlock; 
       // Accumulated BRDs per share per energy, times 1e12. See below. 
       uint256 accBRDPerShare; 
       // Accumulated Share
       uint256 accShare;
       // knownsec share cumulative
       }
    /* ========== STATES ========== */
    // The BRD ERC20 token 
    IBRDToken public BRD;
    // Crypto DODO contract 
    ICryptoDODO public cryptoDODO;// knownsec Encrypted DODO contract
    // dev address. 
    address public devaddr;
    // number of BRD tokens created per block. 
    uint256 public BRDPerBlock;
    // knownsec BRD produced by each block
    // Energy if user does not have any DODO that boost the LP pool
    uint256 public constant EMPTY_DODO_ENERGY = 1;// knownsec DODO incentive
    // Info of each pool. 
    PoolInfo[] public poolInfo;// knownsec Pool information initialization
    // Info of each user that stakes LP tokens. 
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;// knownsec User pledge table
    // Info of each user that stakes LP tokens. 
    mapping(address => UserGlobalInfo) public userGlobalInfo;// knownsec User pledge table
    // Total allocation poitns. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;
    // The block number when BRD mining starts. 
    uint256 public startBlock;
    /* ========== CONSTRUCTOR ========== */
    constructor( IBRDToken _BRD, 
    ICryptoDODO _cryptoDODO, 
    address _devaddr,
    uint256 _BRDPerBlock,
    uint256 _startBlock) 
    public { 
    BRD = _BRD;
    cryptoDODO = _cryptoDODO;
    devaddr = _devaddr; 
    BRDPerBlock = _BRDPerBlock;
    startBlock = _startBlock; 
        
    }
    /* ========== PUBLIC ========== */
    /** * @dev get number of LP pools */ 
    function poolLength() external view returns (uint256) {
        // knownsec External call to obtain the number of pool information (poolInfo)
       return poolInfo.length; 
        
    }
    /** * @dev Add a new lp to the pool. Can only be called by the owner. 
    * DO NOT add the same LP token more than once. Rewards will be messed up if you do. */ 
    function add( uint256 _allocPoint, IERC20 _lpToken, bool _withUpdate ) public onlyOwner {
        if (_withUpdate) { 
            massUpdatePools(); 
            
        } 
        uint256 lastRewardBlock = block.number > startBlock ? block.number : startBlock;
        totalAllocPoint = totalAllocPoint.add(_allocPoint); 
        poolInfo.push(PoolInfo({ 
                     lpToken:_lpToken, 
                     allocPoint:_allocPoint,
                     lastRewardBlock: lastRewardBlock,
                     accBRDPerShare: 0,
                     accShare: 0 
                     }) 
                     
                ); 
    }
    /** * @dev Update the given pool's BRD allocation point. Can only be called by the owner. */ 
    function set( uint256 _pid, uint256 _allocPoint, bool _withUpdate ) public onlyOwner { 
        if (_withUpdate) {
            
            massUpdatePools(); 
            
        } 
        totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add( _allocPoint );
        poolInfo[_pid].allocPoint = _allocPoint;
    }
    /** * @dev View `_user` pending BRDs for a given `_pid` LP pool. */ 
    function pendingBRD(uint256 _pid, address _user) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user]; 
        UserGlobalInfo storage userGlobal = userGlobalInfo[msg.sender];
        uint256 accBRDPerShare = pool.accBRDPerShare; 
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (block.number > pool.lastRewardBlock && lpSupply != 0) { 
            uint256 multiplier = _getMultiplier( pool.lastRewardBlock,block.number ); 
            uint256 BRDReward = multiplier .mul(BRDPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
            accBRDPerShare = accBRDPerShare.add( BRDReward.mul(1e12).div(pool.accShare) ); 
            
        } return user .amount .mul(_safeUserDODOEnergy(userGlobal)).mul(accBRDPerShare).div(1e12).sub(user.rewardDebt);
        
    }
    /** * @dev Update reward variables for all pools. Be careful of gas spending! */ 
    function massUpdatePools() public { 
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid); 
            
        } 
        
    }
    /** * @dev Update reward variables of the given pool to be up-to-date. */ 
    function updatePool(uint256 _pid) public { 
        PoolInfo storage pool = poolInfo[_pid]; 
        if (block.number <= pool.lastRewardBlock){ 
            return; 
            
        }
    uint256 lpSupply = pool.lpToken.balanceOf(address(this));
    if (lpSupply == 0) { 
        pool.lastRewardBlock = block.number;
        return; 
        }
    uint256 multiplier = _getMultiplier(pool.lastRewardBlock, block.number); 
    uint256 BRDReward = multiplier .mul(BRDPerBlock) .mul(pool.allocPoint) .div(totalAllocPoint);
    BRD.mint(devaddr, BRDReward.div(10)); 
    BRD.mint(address(this), BRDReward);
    pool.accBRDPerShare = pool.accBRDPerShare.add( BRDReward.mul(1e12).div(pool.accShare) );
    pool.lastRewardBlock = block.number; 
    }
     /** * @dev Retrieve caller's DODO. */ 
     function retrieve() public {
         // knownsec Public method to retrieve the caller's DODO 
         UserGlobalInfo storage userGlobal = userGlobalInfo[msg.sender];
         // knownsec Query the caller userGlobal object in the userGlobalInfo table
         require( userGlobal.DODOID != 0, "MasterChef: you do not have any DODO" );
        for (uint256 pid = 0; pid < poolInfo.length; pid++) {// knownsec Pool information traversal 
           UserInfo storage user = userInfo[pid][msg.sender];
           if (user.amount > 0) {// knownsec Traverse until the user has a balance in the pool, then process 
           PoolInfo storage pool = poolInfo[pid];
              updatePool(pid);
              uint256 pending = user.amount.mul(userGlobal.DODOEnergy).mul(pool.accBRDPerShare).div(1e12).sub(user.rewardDebt); if (pending > 0) { _safeBRDTransfer(msg.sender, pending); 
                  
              }
          user.rewardDebt = user .amount.mul(EMPTY_DODO_ENERGY).mul(pool.accBRDPerShare).div(1e12);
          pool.accShare = pool.accShare.sub((userGlobal.DODOEnergy.sub(1)).mul(user.amount) ); 
               
           } 
            
        } 
        uint256 prevDODOID = userGlobal.DODOID; 
        userGlobal.DODOID = 0; 
        userGlobal.DODOEnergy = 0;
        cryptoDODO.safeTransferFrom( address(this), msg.sender, prevDODOID, 1, "" );
        
         
     }
        /** * @dev Deposit LP tokens to MasterChef for BRD allocation. */ 
        function deposit(uint256 _pid, uint256 _amount) public { 
            PoolInfo storage pool = poolInfo[_pid]; 
            UserInfo storage user = userInfo[_pid][msg.sender];
            UserGlobalInfo storage userGlobal = userGlobalInfo[msg.sender]; 
            updatePool(_pid);
            if (user.amount > 0) { 
                
                uint256 pending = user.amount.mul(_safeUserDODOEnergy(userGlobal)).mul(pool.accBRDPerShare).div(1e12).sub(user.rewardDebt);
                if (pending > 0) { 
                    _safeBRDTransfer(msg.sender, pending); 
                    
                } 
                
            }
            if (_amount > 0) { 
                pool.lpToken.safeTransferFrom( address(msg.sender),address(this),_amount ); 
                user.amount = user.amount.add(_amount); 
                pool.accShare = pool.accShare.add( _safeUserDODOEnergy(userGlobal).mul(_amount) ); 
                
            }
            user.rewardDebt = user .amount .mul(_safeUserDODOEnergy(userGlobal)) .mul(pool.accBRDPerShare) .div(1e12); emit Deposit(msg.sender, _pid, _amount); 
            
        }
        /** * @dev Withdraw LP tokens from MasterChef. */
        function withdraw(uint256 _pid, uint256 _amount) public { 
            PoolInfo storage pool = poolInfo[_pid]; 
            UserInfo storage user = userInfo[_pid][msg.sender]; 
            require(user.amount >= _amount, "MasterChef: invalid amount");
            UserGlobalInfo storage userGlobal = userGlobalInfo[msg.sender];
            updatePool(_pid); 
            uint256 pending = user .amount .mul(_safeUserDODOEnergy(userGlobal)) .mul(pool.accBRDPerShare) .div(1e12) .sub(user.rewardDebt); 
            if (pending > 0) {
                
                _safeBRDTransfer(msg.sender, pending);
               
            } 
            if (_amount > 0) { 
                user.amount = user.amount.sub(_amount);
                pool.lpToken.safeTransfer(address(msg.sender), _amount);
                pool.accShare = pool.accShare.sub( _safeUserDODOEnergy(userGlobal).mul(_amount) );
                }
            user.rewardDebt = user .amount .mul(_safeUserDODOEnergy(userGlobal)) .mul(pool.accBRDPerShare) .div(1e12); 
            
            emit Withdraw(msg.sender, _pid, _amount); 
            
        }
         /* ========== PRIVATE ========== */
        function _safeUserDODOEnergy(UserGlobalInfo storage userGlobal)// knownsec Private method Get userDODOEnergy
        private view returns (uint256) { 
            if (userGlobal.DODOEnergy == 0) {
                return EMPTY_DODO_ENERGY; 
                
            } 
            
            return userGlobal.DODOEnergy; 
            
        }
        // Safe BRD transfer function, just in case if rounding error causes pool to not have enough BRDs. 
        function _safeBRDTransfer(address _to, uint256 _amount) private {
            // knownsec Private method transfer out of BRD
        uint256 BRDBal = BRD.balanceOf(address(this));// knownsec Get contract BRD balance 
        if (_amount > BRDBal) {
            // knownsec Not enough balance 
            BRD.transfer(_to, BRDBal); 
            
        } else { 
            BRD.transfer(_to, _amount);
            
           } 
            
    }
    // Return reward multiplier over the given _from to _to block. 
    function _getMultiplier(uint256 _from, uint256 _to) private pure returns (uint256) { 
     return _to.sub(_from); 
     
    }
    /* ========== EXTERNAL DEV MUTATION ========== */
    // Update dev address by the previous dev. 
    function setDev(address _devaddr) external onlyDev {
        // knownsec dev is available, change dev address 
        devaddr = _devaddr; 
        
    }
    /* ========== EXTERNAL OWNER MUTATION ========== */
    // Update number of BRD to mint per block 
    function setBRDPerBlock(uint256 _BRDPerBlock) external onlyOwner {// knownsec The administrator isavailable, change mining revenue 
    
    BRDPerBlock = _BRDPerBlock; 
    
    }
    /* ========== ERC1155Receiver ========== */
    /** * @dev onERC1155Received implementation per IERC1155Receiver spec */ 
    function onERC1155Received( address, address _from, uint256 _id, uint256, bytes calldata ) external override returns (bytes4) {
        require( msg.sender == address(cryptoDODO), "MasterChef: received DODO from unauthenticated contract" );
        require(_id != 0, "MasterChef: invalid DODO");
        UserGlobalInfo storage userGlobal = userGlobalInfo[_from];
        // Fetch DODO energy 
        (, , , , , , , , , , , uint256 energy, ) = cryptoDODO.getDODO(_id);
        require(energy > 0, "MasterChef: invalid DODO energy");
        for (uint256 i = 0; i < poolInfo.length; i++) {// knownsec Traverse the _from address balance income in the pool for distribution
         UserInfo storage user = userInfo[i][_from];
         if (user.amount > 0) { PoolInfo storage pool = poolInfo[i];
          updatePool(i);
          uint256 pending = user .amount.mul(_safeUserDODOEnergy(userGlobal)).mul(pool.accBRDPerShare).div(1e12).sub(user.rewardDebt);
          if (pending > 0) { 
              _safeBRDTransfer(_from, pending);
          }// knownsec Calculate the reward to be transferred and transfer
          // Update user reward debt with new energy 
          user.rewardDebt = user .amount.mul(energy).mul(pool.accBRDPerShare).div(1e12);
          pool.accShare = pool.accShare.add(energy.mul(user.amount)).sub( _safeUserDODOEnergy(userGlobal).mul(user.amount) );// knownsec Update accshare 
         } 
            
            
    }
     // update user global
    // knownsec Update useGlobal information 
    uint256 prevDODOID = userGlobal.DODOID; 
    userGlobal.DODOID = _id; 
    userGlobal.DODOEnergy = energy;
    // Give original owner the right to breed
    // knownsec Issue of reproduction rights 
    cryptoDODO.grandPermissionToBreed(_from, _id);
    if (prevDODOID != 0) { // Transfer DODO back to owner 
    cryptoDODO.safeTransferFrom( address(this),_from,prevDODOID,1,"" ); 
        
    }
    return bytes4( keccak256( "onERC1155Received(address,address,uint256,uint256,bytes)" ) ); 
        
    }
     /** * @dev onERC1155BatchReceived implementation per IERC1155Receiver spec * User should not send using batch. */ 
     function onERC1155BatchReceived( address, address, uint256[] memory, uint256[] memory, bytes memory ) external override returns (bytes4) {
         return ""; 
         
     }
       /* ========== MODIFIER ========== */
    modifier onlyDev() { 
        require(devaddr == _msgSender(), "Masterchef: caller is not the dev");// knownsec Access control
        _;
        
        
    }
        
    
}