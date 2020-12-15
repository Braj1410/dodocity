// SPDX-License-Identifier: MIT
pragma solidity =0.6.12;
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/token/ERC1155/ERC1155Receiver.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/math/Math.sol";
import "@openzeppelin/contracts/utils/EnumerableSet.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./DateControl.sol";
contract AlpacaPresale is Ownable, DateControl, ReentrancyGuard, ERC1155Receiver{
 using SafeMath for uint256; 
 using Math for uint256; 
 using EnumerableSet for EnumerableSet.UintSet;
 using EnumerableSet for EnumerableSet.AddressSet;
 /* ========== STATE VARIABLES ========== */
 IERC1155 public cryptoAlpaca;
 uint256 public pricePerAlpaca = 0.01 ether;
 uint256 public maxAdoptionCount = 100;
 // Mapping from address to alpaca count  
  mapping(address => uint256) private accountAddoptionCount;
 // Set of alpaca IDs this contract owns 
 EnumerableSet.UintSet private presaleAlpacaIDs;
 // Set of address that are approved to purchase alpaca 
 EnumerableSet.AddressSet private whitelist;
 /* ========== CONSTRUCTOR ========== */
 constructor(IERC1155 _cryptoAlpaca) public { 
     cryptoAlpaca = _cryptoAlpaca; 
     }
 /* ========== OWNER ONLY ========== */
 /** * @dev Allow owner to change alpaca price */
  function addToWhitelist(address[] calldata _addresses) public onlyOwner { 
      for (uint256 i = 0; i < _addresses.length; i++) { 
          whitelist.add(_addresses[i]); 
        } 
    }
 /** * @dev Allow owner to change alpaca price */ 
 function setPricePerAlpaca(uint256 _price) public onlyOwner { 
     pricePerAlpaca = _price; 
    }
 /** * @dev Allow owner to update maximum number alpaca a given user can adopt */ 
 function setMaxAdoptionCount(uint256 _maxAdoptionCount) public onlyOwner {
      maxAdoptionCount = _maxAdoptionCount; 
    }
 /** * @dev Allow owner to transfer a alpaca that didn't get adopted during presale */ 
    function reclaim(uint256 _id, address _to) public onlyOwner whenEnded{
        
        cryptoAlpaca.safeTransferFrom(address(this), _to, _id, 1, ""); 
        
    }
 /** * @dev Allow owner to transfer all alpaca that didn't get adopted during presale */ 
    function reclaimAll(address _to) public onlyOwner whenEnded { 
      
      uint256 length = presaleAlpacaIDs.length();
      uint256[] memory ids = new uint256[](length); 
      uint256[] memory amount = new uint256[](length); 
      
      for (uint256 i = 0; i < length; i++) { 
       ids[i] = presaleAlpacaIDs.at(i); amount[i] = 1;
      }
      cryptoAlpaca.safeBatchTransferFrom(address(this), _to, ids, amount, ""); 
    }
      /** * @dev Allows owner to withdrawal the presale balance to an account. */ 
     function withdraw(address payable _to) external onlyOwner { 

     _to.transfer(address(this).balance); 
     
     }
     /* ========== EXTERNAL MUTATIVE FUNCTIONS ========== */
     /** * @dev Adopt _count number of alpaca */ 
     function adoptAlpaca(uint256 _count) public payable whenInProgress nonReentrant {
         require(_count > 0, "AlpacaPresale: must adopt at least one alpaca");
         require(whitelist.contains(msg.sender), "AlpacaPresale: unauthorized");
         address account = msg.sender; 
         uint256 credit = canAdoptCount(account); 
         require(_count <= credit, "AlpacaPresale: adoption count larger than maximum adoption limit" );
         require(msg.value >= getAdoptionPrice(_count), "AlpacaPresale: insufficient funds" );
         uint256[] memory ids = new uint256[](_count); 
         uint256[] memory counts = new uint256[](_count); 
         for (uint256 i = 0; i < _count; i++) { 
             
             ids[i] = _randRemoveAlpaca();
             counts[i] = 1;
        }

         accountAddoptionCount[account] += _count;//knownsec// Accumulate the number of adoptions
             cryptoAlpaca.safeBatchTransferFrom(address(this), account, ids, counts, "" );
             
             
    }
           /* ========== VIEW ========== */
        /** * @dev returns if `_account` is whitelisted to adopt alpaca */ 
        function allowedToAdopt(address _account) public view returns (bool) { 
            return whitelist.contains(_account);
         }
        /** * @dev returns number of _account has adopted presale alpaca */
         function getAdoptionCount(address _account) public view returns (uint256) { 
             return accountAddoptionCount[_account]; 
            }
        /** * @dev total adoption price if adopt _count many */ 
        function getAdoptionPrice(uint256 _count) public view returns (uint256) { 
            return _count.mul(pricePerAlpaca); 
            }
        /** * @dev number of presale alpaca this contract owns */ 
         function getPresaleAlpacaCount() public view returns (uint256) {
              return presaleAlpacaIDs.length(); 
            }
        /** * @dev how many more _account can adopt alpaca */ 
        function canAdoptCount(address _account) public view returns (uint256) { 
            if (!allowedToAdopt(_account)) { 
                return 0; 
                }
            uint256 credit = maxAdoptionCount.sub(accountAddoptionCount[_account]);
            uint256 alpacaCount = presaleAlpacaIDs.length();
            return credit.min(alpacaCount); 
        }
         /** * @dev onERC1155Received implementation per IERC1155Receiver spec */ 
         function onERC1155Received( address, address, uint256 id, uint256, bytes calldata ) external override returns (bytes4) { 
             require(msg.sender == address(cryptoAlpaca), "AlpacaPresale: received alpaca from unauthenticated contract" );
             uint256[] memory ids = new uint256[](1); ids[0] = id;
             _receivedAlpaca(ids);
             return bytes4( keccak256( "onERC1155Received(address,address,uint256,uint256,bytes)" ) ); 
         }
         /** * @dev onERC1155BatchReceived implementation per IERC1155Receiver spec */ 
         function onERC1155BatchReceived( address, address, uint256[] calldata ids, uint256[] calldata, bytes calldata ) external override returns (bytes4) {
              require( msg.sender == address(cryptoAlpaca), "AlpacaPresale: received alpaca from unauthenticated contract" );
             _receivedAlpaca(ids);
             return bytes4( keccak256( "onERC1155BatchReceived(address,address,uint256[],uint256[],bytes)" ) ); }
         /* ========== PRIVATE ========== */
         /** * @dev randomly select and remove a alpaca * returns selected alpaca ID */ 
         function _randRemoveAlpaca() private returns (uint256) {
             require(presaleAlpacaIDs.length() > 0, "No more presale alpaca");
             uint256 totalLength = presaleAlpacaIDs.length();
             uint256 randIndex = uint256(blockhash(block.number - 1)); 
             randIndex = uint256(keccak256(abi.encodePacked(randIndex, totalLength))) .mod(totalLength);
             uint256 randID = presaleAlpacaIDs.at(uint256(randIndex));
             require(presaleAlpacaIDs.remove(randID));
             return randID; }
             function _receivedAlpaca(uint256[] memory ids) private { 
                 for (uint256 i = 0; i < ids.length; i++) { presaleAlpacaIDs.add(ids[i]); 
                 } 
        }
        
 }
