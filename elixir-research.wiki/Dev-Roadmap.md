- [ ] finish chainstate checks [#10](../issues/10)
- [ ] remove transactions from pool on adding block [#59](../issues/59)
- [ ] mining for number of cycles to allow fast suspending [#60](../issues/60)
- [ ] write test-suites for basic blockchain [#57](../issues/57) [#58](../issues/58)
- [ ] increment transaction nonce for every outgoing transaction 
- [ ] add fee to transaction [#83](../issues/83)
- [ ] check public key length in transaction validity [#84](../issues/84)
- [ ] validate difficulty target [#85](../issues/85)
- [ ] refactor chain to be map of blocks, traverse top to bottom

### release `0.1-local-blockchain`

- [ ] sync ping-pong example [#41](../issues/41) [#52](../issues/52)
- [ ] manually add peers [#53](../issues/53)
- [ ] provide get all peers endpoint [#78](../issues/78)
- [ ] provide `get_info` endpoint [#69](../issues/69)
- [ ] periodic check for peers current block hash [#77](../issues/])
- [ ] broadcast new block to all peers [#75](../issues/75)
- [ ] broadcast new transactions to all peers [#68](../issues/68)
- [ ] provide `get_block_by_hash` endpoint [#76](../issues/76)
- [ ] format addresses in json as base58 [#86](../issues/86)
- [ ] continue mining on newest block, if received [#80](../issues/80)
- [ ] implement initial sync from latest block to genesis block
- [ ] ignore own peer in handling peers [#79](../issues/79)
- [ ] recognize invalid chain
- [ ] implement nakamoto consensus, follow longest valid chain

### release `0.2-synced-blockchain`

- [ ] write blockchain and chainstate to disk on shutdown
- [ ] read blockchain and chainstate from disk on startup
- [ ] use rocksdb to read/write blocks by hash

### release `0.3-synced-persistent-blockchain`

