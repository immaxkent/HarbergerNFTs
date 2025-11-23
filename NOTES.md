# Harberger NFTs Basic Design Specification

The following is a basic design specification for a Harberger NFTs system. It is intended to be a starting point for development and a place to note some of the design considerations given to the architecture during implementation.

## Design Notes

The following are design notes made through implementation of the codebase.

1. We use mappings to store metadatas as they present a more gas efficient way to cover storage layouts and access than, say, dedicated structs, specifically where structs (or at least, chunks of data) are NOT being passed function to function or contreact to contract.
2. Modification of the NFT requires immediate payment of outstanding tax in this design. There are a number of options here, but would lie in the field of 'product' more than 'engineering'. As such, if this contract/architecture were to move to production this factor may be given more scrutiny (e.g. compound the interest accrued with the new interest rate post timestamp `t`, or whatever). The 'shape' of this element in this design has been elected for simplicity.
3. Consideration was given to adding a per NFT tax rate, for customisability during mint, but felt it just added more complexity without a large increase in design elegance. The angle taken here was 'those minting Harberger NFTs would be incentivised to write as near-zerro tax rate as possible since that levy falls on their head', and as such this was left to governance.
4. Tokens minted are given value and charged tax in units of Ether. This is a design choice and may be changed in the future similarly to other architecture design aspects.
5. This design sees defaulted NFTs are unable to be purchased back from the treasury. Again, this is a design choice and is liable to design change if taken to production.
6. Purchasing does not allow re-definition of the price/value of the NFT in the same call. This should be done in a subsequent call to `modify`
7. Two functions exist for analysing tax: one returns _tax due_, whilst the other _evaluates tax status_ AND provides for _defaulting_ (where NFTs are repossessed by the treasury). The latter serves as an endpoint for automatic tax evaluation (on owner call) and/or maintainer driven tax analysis.
8. The `evaluate()` function may be called by some sort of protocol maintainer, e.g. a server side repo run via cron job on github or similar OR an EOA OR the owner .... or whatever. Again, this aspect is left to iteration if taken to production, but noted ehre for conciceness and brevity in design analysis.
9. Extends OpenZeppelin's ERC721 contract.

## Harberger Taxation System

A Harberger NFT is a token that is subject to a tax rate levied proportionally to value of the NFT. In this design, tax is paid in Ether. Some notes on design decisions:

- We can apply some rate X to yield an annual tax rate X% for owning an asset
- Taxes MUST be paid via contract and are assigned to the tax recipient (lets calll it `treasury`)
- We can put an evaluative cliff in place (say 6 months?) during deployment, modifyable via setters, for the payment of taxes (half a year) and ensure we have covered twice block time past that cliff to check for tax payments. If unpaid, the asset is confiscated and 'sold' (transferred) to the treasury.
- This call happens automatically on the attempt of tax payment OR on an external call by some maintainer (should be open source/public(or external))
- The `evaluateAndAddress()` function is called automatically on the attempt of tax payment OR modification OR purchase on an external call by some maintainer (should be open source/public(or external)) - and this function specifically handles defaults

**Modifiers**

- `blockTimeMargin(tokenId)` :: takes the `timestamp` for any given NFT and adds two blocks (24 + 1 seconds), and checks if the current block timestamp is outside of this margin. Reverts if not. Used specifically for _purchasing_ and _modifying_ to ensure the tax rate can't be changed without paying due tax, since we use `block.timestamp`, which is non-specific.

**Global Variables**

-`treasurer` :: An `address` representing the address of the treasurer. Should be initialized in constructor

- `MAX_PRICE` :: A `uint256` representing the maximum price of an NFT. Capped at 10^18 ETH. Should be initialized in the constructor
- `MIN_PRICE` :: A `uint256` representing the minimum price of an NFT. Capped at 0.001ETH. Should be initialized in the constructor
- `GLOBAL_TAX_RATE` :: A `uint256` global tax rate for NFTs. Capped at 100% e.g. 10_000. Includes getter and setter. Should be initialized in the constructor
<!-- - `CustomTaxRates` :: A `mapping` of `tokenId` to `uint256` allowing the setting of custom tax rates for any given token at either `mint` or `modify` -->
- `Cliff` :: A `uint256` representing the number of seconds after minting/modification that **tax must be paid** (a margin should be given, say 2 blocks). Includes getter and setter. Should be initialized in the constructor
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
2. if not defaulted, calls `evaluateAndAddress()` and returns the tax due (or confiscates the NFT to the treasury)
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

- `evaluateAndAddress(params) public payable`

1. takes in a tokenId
2. analyses tax due by calling `returnTaxDue`
3. analyses tax status:
   2.1 if it **hasn't** elapsed the cliff, it returns tax paid and next tax due date and tax owed at _current time_ (`block.timestamp`) by analysing this against the timestamp of minting/modifying. Use basic tax formula using annual rate `tax = (price * taxRate * secondsElapsed) / (365 days * 10_000))`
   2.2 if tax due **has** elapsed the cliff, it automatically reposseses the NFT to the treasury via calling `transferFrom`, and marks the NFT as defaulted in the respective mapping

- `returnTaxDue(tokenId)`

1. takes tokenId and returns the `taxDue` based on the price and time elapsed since last payment wrt global tax rate. Should scale 1e18 to ensure a good degree of precision

- `payTax(params)`

1. calls `returnTaxDue()`, passing in the tokenId, and assumably taking the positive path and returning the `taxDue`
2. transfers that amount of 'tax' from `msg.sender` as a `.call` call, passing in `({value: taxDue})`

## Notes for Owner

- maintenance calls should be made REGULARLY to prevent overflow. E.g. if time elapsed is 10 years you may experience overflow with a very high valued NFT
- MAX_PRICE is initialised in the constructor - its maximum value is 10^18 ETH. This should be modified **in contract** if a higher value may be desired
- `GLOBAL_TAX_RATE` is initialised in the constructor - its maximum vate is 100%. This should be modified **in contract** if a higher value may be desired, and addressed in checks both in constructor and setter for `GLOBAL_TAX_RATE`
