# Design Specification

This document contains a specification for the Harberger MFT architecture. This spec has been derived from a provided brief.

**Modifiers**

- `blockTimeMargin(tokenId)` :: takes the `timestamp` for any given NFT and adds two blocks (24 + 1 seconds), and checks if the current block timestamp is outside of this margin. Reverts if not. Used specifically for _purchasing_ and _modifying_ to ensure the tax rate can't be changed without paying due tax, since we use `block.timestamp`, which is non-specific.

**Global Variables**

-`treasurer` :: An `address` representing the address of the treasurer. Should be initialized in constructor

- `MAX_PRICE` :: A `uint256` representing the maximum price of an NFT. Capped at 10^18 ETH. Should be initialized in the constructor
- `MIN_PRICE` :: A `uint256` representing the minimum price of an NFT. Capped at 0.001ETH. Should be initialized in the constructor
- `GLOBAL_TAX_RATE` :: A `uint256` global tax rate for NFTs. Capped at 100% e.g. 10_000. NO setter to be implemented, as was not requried in brief and adds complexity. Should be initialized in the constructor
<!-- - `CustomTaxRates` :: A `mapping` of `tokenId` to `uint256` allowing the setting of custom tax rates for any given token at either `mint` or `modify` -->
- `Cliff` :: A `uint256` representing the number of seconds after minting/modification that **tax must be paid** (a margin should be given, say 2 blocks). NO setter to be implemented, as was not requried in brief and adds complexity. Should be initialized in the constructor
- `nftPrices` :: A mapping of `tokenId` to `uint256` representing the price of the NFT.
- `nftTimestamps` :: A mapping of `tokenId` to `uint64` representing the timestamp of the last modification of the NFT (initialised at block.timestamp at time of minting)
- `defaultedNFTs` :: A mapping of `tokenId` to `bool` representing whether an NFT is defaulted

**Functions**

- `constructor(params)`

1. initializes the global tax rate
2. initializes the cliff
3. sets the treasurer address

- `mint(params)`

1. mints an ERC721 NFT
2. takes a parameter for `value` which is stored in a mapping. Must be non-zero
3. writes value of `timestamp` to record time of minting/modification

- `modify(params)`

allows modification of the value for any given NFT, callable only by token owner.

1. check status of NFT in `defaultedNFTs` array
2. if not defaulted, calls `returnTaxDue()` and returns the tax due (or confiscates the NFT to the treasury)
3. charges the tax due to the owner based on the old price, requiring success in transfer
4. updates the price in the mapping

N.B. Each time this is called, the tax rate is calculated based on the global tax rate

- `purchase(params) public payable`

allows any NFT to be purchased by any address at the mapped price, callable by any address

1. takes in a tokenId
2. reads price from the mapping
3. calculates tax due via calling `returnTaxDue`
4. transfers the price from the buyer to the owner, and the tax due to the treasury (yes, the new purchaser pays due tax)
5. transfers the NFT from the owner to the buyer via `transferFrom`
6. updates the timestamp in the mapping

- `evaluateAndAddress(params) public payable` **THIS IS OUR FROECLOSURE PATH**

1. takes in a tokenId
2. analyses time delta between current block timestamp and the timestamp of minting/modifying
3. analyses default status:
   2.1 if it **hasn't** elapsed the cliff, return `false`. Use basic tax formula using annual rate
   2.2 if tax due **has** elapsed the cliff, it automatically reposseses the NFT to the treasury via calling `transferFrom`, and marks the NFT as defaulted in the respective mapping. Return `true`.

- `returnTaxDue(tokenId)`

1. takes tokenId and returns the `taxDue` based on the price and time elapsed since last payment wrt global tax rate. Should scale 1e18 to ensure a good degree of precision. Use the basic tax formula using annual rate, e.g. `tax = (price * taxRate * secondsElapsed) / (365 days * 10_000))`

- `payTax(params)`

1. calls `returnTaxDue()`, passing in the tokenId, and assumably taking the positive path and returning the `taxDue`
2. transfers that amount of 'tax' from `msg.sender` as a `.call` call, passing in `({value: taxDue})`

## Notes for Owner

- maintenance calls should be made REGULARLY to prevent overflow. E.g. if time elapsed is 10 years you may experience overflow with a very high valued NFT
- MAX_PRICE is initialised in the constructor - its maximum value is 10^18 ETH. This should be modified **in contract** if a higher value may be desired
- `GLOBAL_TAX_RATE` is initialised in the constructor - its maximum vate is 100%. This should be modified **in contract** if a higher value may be desired, and addressed in checks both in constructor and setter for `GLOBAL_TAX_RATE`
