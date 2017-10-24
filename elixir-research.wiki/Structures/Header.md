### Header Structure
  The header structure contains most the information of a single block:

| Description      |      Type     |  Comments |
|:------------------|:-------------|:-----------|
| height   		     | int 		       | The height of the this block |
| prev_hash        | binary        | The hash value of the previous block |
| txs_hash         | binary        | The reference to a Merkle tree collection which is a hash of all transactions related to this block |
| chain_state_hash | binary		     | The reference to a Merkle tree collection which is a hash of all transaction amounts in this block |
| difficulty_target| int		       | The measure of how difficult it is to find a hash below a given target |
| nonce   		     | int   		     | The nonce used to generate this block |
| timestamp        | int	   	     | A timestamp recording when this block was created |
| version          | int	   	     | Block version |

#### Height
  Height field is used as helper field for easier development. Used mainly for
  validation of the blockchain and visual aid of which block is which.

***

#### Previous hash
  Previous hash field is very special and important field in the block. It is one of many
  guards against cheating and corrupting the blockchain. When we have this field we can
  guarantee that the integrity of the blockchain stays stable and linear.

  For more information about validating the prev_hash see - Validation

***

#### Transaction hash
  Transaction hash is the hash of the Merkle tree root, see [Merkle Tree](https://en.wikipedia.org/wiki/Merkle_tree).

  The Merkle tree root is constructed by hashing pairs of individual transactions
  in the block, this helps to keep the block size small, because we keep only one
  hash instead of all transaction hashes.

  For more information about validating the txs_hash see - Validation

***

#### Chainstate hash
  Chainstate hash is the hash of the Merkle tree root, see [Merkle Tree](https://en.wikipedia.org/wiki/Merkle_tree).

  The Merkle tree consists of multiple key-value entries where the key is the
  individual accounts and the value is the balance associated with this account.
  The chainstate hash is the hash of the root of the Merkle tree.

  For more information about validating the chain_state_hash see - Validation

***

#### Difficulty target
  Difficulty represents how difficult the current target makes it to find a block,
  relative to how difficult it would be at the highest possible target. It is
  usually given by number of consecutive zeros that a hash should start with.


  Right now the difficulty changes every 100 blocks and it is adjusted based on
  how much time did it take to mine the previous 100 blocks

***

#### Nonce
  A field whose value is set so the hash of the block meets the target difficulty.
  The miner increments the nonce until the target is met.

***

#### Version
  The current version of the blockchain software
