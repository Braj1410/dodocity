// SPDX-License-Identifier: MIT
pragma solidity =0.6.12;
import "../interfaces/IGeneScience.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
contract GeneScience is IGeneScience {
  
  using SafeMath for uint256;// knownsec How to import SafeMath
  /* ========== STATE VARIABLES ========== */
   uint256 private constant _maskLast8Bits = uint256(0xff);
   uint256 private constant _maskFirst248Bits = uint256(~0xff);
   uint256 private constant BASE_GENERATION_FACTOR = 10;
   uint256 private constant ENERGY_BUFF = 2;
   /* ========== CONSTRUCTOR ========== */
   constructor() public {}
   /* ========== VIEWS ========== */
   /** * Conform to IGeneScience */ 
   function isDODOGeneScience() external override pure returns (bool) {
     return true; 
    }
   struct LocalStorage { 
     uint8[48] genes1Array; 
     uint8[48] genes2Array; 
     uint8[48] babyArray; 
     uint8 swap; uint256 rand; 
     uint256 randomN;
     uint256 traitPos; 
     uint256 randomIndex; 
     uint256 baseEnergy; 
     bool applyEnergyBuff; }
      /** * @dev given genes of alpaca 1 & 2, return a genetic combination *
       @param _genes1 genes of matron * 
     @param _genes2 genes of sire *
     @param _generation child generation * 
     @param _targetBlock target block child is intended to be born * 
     @return gene child gene * 
     @return energy energy associated with the gene * 
     @return generationFactor buffs child energy, 
     higher the generation larger the generationFactor * energy = gene energy * generationFactor */

   function mixGenes( 
      uint256 _genes1,
      uint256 _genes2, 
      uint256 _generation, 
      uint256 _targetBlock) 
      external override view returns ( 
          uint256 gene, 
          uint256 energy, 
          uint256 generationFactor )
          {
     
            LocalStorage memory store; // knownsec Instantiate LocalStorage object 
            require(block.number > _targetBlock);


            // Try to grab the hash of the "target block". This should be available the vast 
            // majority of the time (it will only fail if no-one calls giveBirth() within 256
            // blocks of the target block, which is about 40 minutes. Since anyone can call 
            // giveBirth() and they are rewarded with ether if it succeeds, this is quite unlikely.) 
     
           store.randomN = uint256(blockhash(_targetBlock));
          // knownsec Initialize randomN
           if (store.randomN == 0) {
           // knownsec Handle the case of unsuccessful initialization of randomN 
           // We don't want to completely bail if the target block is no-longer available, 
           // nor do we want to just use the current block's hash (since it could allow a 
           // caller to game the random result). Compute the most recent block that has the 
           // the same value modulo 256 as the target block. The hash for this block will 
           // still be available, and – while it can still change as time passes – it will 
           // only change every 40 minutes. Again, someone is very likely to jump in with 
           // the giveBirth() call before it can cycle too many times. 
        
             _targetBlock = (block.number & _maskFirst248Bits) +(_targetBlock & _maskLast8Bits);

           // The computation above could result in a block LARGER than the current block, 
           // if so, subtract 256. 
           if (_targetBlock >= block.number) _targetBlock -= 256;
         
             store.randomN = uint256(blockhash(_targetBlock)); 
        }
        // generate 256 bits of random, using as much entropy as we can from // sources that can't change between calls. 

        store.randomN = uint256( keccak256( abi.encodePacked( store.randomN, _genes1, _genes2, _generation, _targetBlock, block.timestamp, block.difficulty ) ) );
        store.randomIndex = 0;
        // knownsec Initialize randomIndex 
        store.genes1Array = _decode(_genes1);
        // knownsec Initialize genes1Array 
        store.genes2Array = _decode(_genes2);
        // knownsec Initialize genes2Array
        // iterate all 12 characteristics 
        for (uint256 i = 0; i < 12; i++) {  

          // pick 4 traits for characteristic i uint256 j; for (j = 3; j >= 1; j--) { store.traitPos = (i * 4) + j;
          store.rand = _sliceNumber(store.randomN, 2, store.randomIndex); // 0~3
          store.randomIndex += 2;
           // 1/4 of a chance of gene swapping forward towards expressing. 
           if (store.rand == 0) { // do it for parent 1
            store.swap = store.genes1Array[store.traitPos];
            store.genes1Array[store.traitPos] = store.genes1Array[store .traitPos - 1]; store.genes1Array[store.traitPos - 1] = store.swap; 
           }
            store.rand = _sliceNumber(store.randomN, 2, store.randomIndex); // 0~3
            store.randomIndex += 2;
          if (store.rand == 0) {   // do it for parent 2
           store.swap = store.genes2Array[store.traitPos];
           store.genes2Array[store.traitPos] = store.genes2Array[store .traitPos - 1]; store.genes2Array[store.traitPos - 1] = store.swap; 
           } 
        } 
    

      
        uint8 prevEnergyType;
        store.applyEnergyBuff = true; 
        
        for (store.traitPos = 0; store.traitPos < 48; store.traitPos++) { 
               store.rand = _sliceNumber(store.randomN, 1, store.randomIndex); 
               // 0 ~ 1 store.randomIndex += 1;
               // 50% pick from store.genes1Array

               if (store.rand == 0) {
                    store.babyArray[store.traitPos] = uint8( store.genes1Array[store.traitPos] ); 
                } 
                else { 
                    store.babyArray[store.traitPos] = uint8( store.genes2Array[store.traitPos] ); 
                }
               /** * Checks for energy buff 
               * Energy buff only check for dominant gene (store.traitPos % 4 == 0) and only first 5 dominant traits (5 traits * 4 gene/traits = 20 gene)
               * Apply ENERGY_BUFF IFF each dominant trait & 8 > 1 and all equal. 
               * For example: 
               * [[*3*, 9, 4, 2], [*11*, 13, 6, 42], [*3*, 24, 16, 1], [*19*, 5, 6, 8], [], ...] 
               * 3 & 8 = 11 & 8 = 3 & 8 = 19 & 8 = 3 (>2) */
               if (store.traitPos % 4 == 0) { uint8 dominantGene = store.babyArray[store.traitPos];
               // short circuit energy buff if already failed
                 if (store.applyEnergyBuff && store.traitPos < 20) { // a trait type is dominant gene mod 8
                     uint8 energyType = dominantGene % 8;
                 // energy buff only applicable to energy type greater than 1 
                    if (energyType < 2) { 
                        store.applyEnergyBuff = false; 
                        } 
                    else { 
                        if (store.traitPos != 0) { 
                            store.applyEnergyBuff = energyType == prevEnergyType; 
                        }
                    prevEnergyType = energyType; 
                    } 
                }
            if (dominantGene < 8) { 
                store.baseEnergy += 1; 
                } 
             else if (dominantGene < 16) { 
                store.baseEnergy += 5; 
            }  else if (dominantGene < 24) {
                 store.baseEnergy += 10;
                 }  
               else {
                    store.baseEnergy += 15; 
                  } 
            } 
        }
          store.rand = _sliceNumber(store.randomN, 2, store.randomIndex); // 0 ~ 3 store.randomIndex += 1;
          generationFactor = _calculateGenerationFactor( store.rand, _generation, store.applyEnergyBuff ); energy = store.baseEnergy.mul(generationFactor); require(energy == uint256(uint64(energy))); gene = _encode(store.babyArray); }
          /* ========== PRIVATE METHOD ========== */
           /** * given a number get a slice of any bits, at certain offset 
           * @param _n a number to be sliced 
           * @param _nbits how many bits long is the new number 
           * @param _offset how many bits to skip */ 
           function _sliceNumber( uint256 _n, uint256 _nbits, uint256 _offset ) private pure returns (uint256) {
               // knownsec Private method, offset slice 
               // mask is made by shifting left an offset number of times 
               uint256 mask = uint256((2**_nbits) - 1) << _offset; 
               // AND n with mask, and trim to max of _nbits bits 
               return uint256((_n & mask) >> _offset);
                }
         /** * Get a 5 bit slice from an input as a number 
         * @param _input bits, encoded as uint
         * @param _slot from 0 to 50 
         */
         function _get5Bits(uint256 _input, uint256 _slot) private pure returns (uint8)// knownsec Private method to obtain 5-bit slice data 
         { 
             return uint8(_sliceNumber(_input, uint256(5), _slot * 5));
          }
         /** * Parse a Alpaca gene and returns all of 12 "trait stack" that makes the characteristics 
         * @param _genes alpaca gene 
         * @return the 48 traits that composes the genetic code, 
           logically divided in stacks of 4, 
           where only the first trait of each stack may express*/ 
           
           function _decode(uint256 _genes) private pure returns (uint8[48] memory) {
               // knownsec Private method to unravel the alpaca gene 
               uint8[48] memory traits; 
               uint256 i; 
               for (i = 0; i < 48; i++) { 
                   traits[i] = _get5Bits(_genes, i); 
                   } 
                   return traits; 
                }
         /** * Given an array of traits return the number that represent genes */
           function _encode(uint8[48] memory _traits) private pure returns (uint256 _genes)// knownsec Private method, encoding gene characteristic value 
           {  _genes = 0;
               for (uint256 i = 0; i < 48; i++) { 
                   _genes = _genes << 5; 
                   // bitwise OR trait with _genes 
                   _genes = _genes | _traits[47 - i]; } 
                   return _genes; 
            }
        /** * calculate child generation factor */ 
           function _calculateGenerationFactor( uint256 _rand, uint256 _generation, bool _applyEnergyBuff ) private pure returns (uint256 _generationFactor) {
               // knownsec Private method, child factor generation algorithm
             _generationFactor = BASE_GENERATION_FACTOR.add( uint256(2).mul(_generation) );
            if (_rand == 0) { _generationFactor = _generationFactor.sub(1);
             } 
            else if (_rand == 1) { 
                _generationFactor = _generationFactor.add(1); 
                }
            if (_applyEnergyBuff) { 
                _generationFactor = _generationFactor.mul(ENERGY_BUFF); 
            } 
        } 
}
