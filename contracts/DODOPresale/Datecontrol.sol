// SPDX-License-Identifier: MIT
pragma solidity =0.6.12;
import "@openzeppelin/contracts/access/Ownable.sol";


contract DateControl is Ownable {


 /* ========== STATE VARIABLES ========== */
 uint256 public startBlock;
 uint256 public endBlock;


 /* ========== EXTERNAL MUTATIVE FUNCTIONS ========== */


 function setStartBlock(uint256 _block) external onlyOwner { 
     
     startBlock = _block; 
     
     }
 function setEndBlock(uint256 _block) external onlyOwner { 
     
     endBlock = _block;
     
     }
 /* ========== MODIFIER ========== */
 modifier whenInProgress() {
      require(block.number >= startBlock, "Event not yet started");
     require(block.number < endBlock, "Event Ended"); 
     _; 

    }
 modifier whenEnded() { 
     require(block.number >= endBlock, "Event not yet ended");
      _; 
     
     } 
}